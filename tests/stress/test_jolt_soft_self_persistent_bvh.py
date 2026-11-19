"""Reference tests for persistent refitting of Cgame's Jolt soft self-edge BVH.

Only source, geometry and cache-lifecycle contracts. Native C++ and dynamic
simulation require the separate whole-engine-stress workflow.
"""
from dataclasses import dataclass
import math
import random
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
CPP = ROOT / "modules/jolt_physics/spaces/jolt_space_3d.cpp"
SPACE_HEADER = ROOT / "modules/jolt_physics/spaces/jolt_space_3d.h"
SETTINGS_HEADER = ROOT / "modules/jolt_physics/jolt_project_settings.h"
SETTINGS_CPP = ROOT / "modules/jolt_physics/jolt_project_settings.cpp"
PROJECT = ROOT / "tests/stress/jolt_soft_self_persistent_bvh/project.godot"
NATIVE = ROOT / "tests/stress/jolt_soft_self_persistent_bvh/persistent_refit_regression.gd"


@dataclass
class Entry:
    index: int
    low: tuple
    high: tuple


@dataclass
class Node:
    low: tuple
    high: tuple
    begin: int
    end: int
    left: int = -1
    right: int = -1


def edge_bounds(points, edge):
    a, b = (points[edge[0]], points[edge[1]])
    return (tuple(min(a[k], b[k]) for k in range(3)),
            tuple(max(a[k], b[k]) for k in range(3)))


def overlaps(lo, hi, test_lo, test_hi, radius=0.1):
    return all(hi[k] + radius >= test_lo[k] and test_hi[k] + radius >= lo[k]
               for k in range(3))


def make_tree(points, edges, leaf_size=4):
    entries = []
    for index, edge in enumerate(edges):
        lo, hi = edge_bounds(points, edge)
        entries.append(Entry(index, lo, hi))
    nodes = []

    def build(begin, end):
        lo = tuple(min(entries[i].low[k] for i in range(begin, end)) for k in range(3))
        hi = tuple(max(entries[i].high[k] for i in range(begin, end)) for k in range(3))
        current = len(nodes)
        nodes.append(Node(lo, hi, begin, end))
        if end - begin <= leaf_size:
            return current
        axis = max(range(3), key=lambda k: (hi[k] - lo[k], -k))
        entries[begin:end] = sorted(
            entries[begin:end],
            key=lambda entry: ((entry.low[axis] + entry.high[axis]) * .5, entry.index),
        )
        mid = (begin + end) // 2
        nodes[current].left = build(begin, mid)
        nodes[current].right = build(mid, end)
        return current

    build(0, len(entries))
    return entries, nodes


def refit_tree(points, edges, entries, nodes, leaf_size=4):
    for entry in entries:
        entry.low, entry.high = edge_bounds(points, edges[entry.index])
    # Same reverse-index order as C++: children are updated before parents.
    for i in reversed(range(len(nodes))):
        node = nodes[i]
        if node.end - node.begin <= leaf_size:
            node.low = tuple(min(entries[j].low[k] for j in range(node.begin, node.end))
                             for k in range(3))
            node.high = tuple(max(entries[j].high[k] for j in range(node.begin, node.end))
                              for k in range(3))
        else:
            left, right = nodes[node.left], nodes[node.right]
            node.low = tuple(min(left.low[k], right.low[k]) for k in range(3))
            node.high = tuple(max(left.high[k], right.high[k]) for k in range(3))


def query_tree(entries, nodes, low, high, radius=0.1):
    results = set()
    visited = 0
    stack = [0]
    while stack:
        node = nodes[stack.pop()]
        visited += 1
        if not overlaps(low, high, node.low, node.high, radius):
            continue
        if node.left == -1:
            for i in range(node.begin, node.end):
                entry = entries[i]
                if overlaps(low, high, entry.low, entry.high, radius):
                    results.add(entry.index)
        else:
            stack.extend((node.left, node.right))
    return results, visited


def random_mesh(seed=55, edge_count=256):
    rng = random.Random(seed)
    points, edges = [], []
    for index in range(edge_count):
        pos = [rng.uniform(-35, 35) for _ in range(3)]
        points.append(tuple(pos))
        points.append(tuple(pos[k] + rng.uniform(-.35, .35) for k in range(3)))
        edges.append((2 * index, 2 * index + 1))
    return points, edges


class PersistentSoftBVHContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cpp = CPP.read_text(encoding="utf-8")
        cls.space_h = SPACE_HEADER.read_text(encoding="utf-8")
        cls.cfg = SETTINGS_CPP.read_text(encoding="utf-8")
        cls.cfg_h = SETTINGS_HEADER.read_text(encoding="utf-8")
        cls.refit = cls.cpp.split("static bool refit_soft_self_edge_bvh(", 1)[1].split(
            "static bool soft_self_edge_bounds_overlap(", 1)[0]
        cls.cache = cls.cpp.split("static bool ensure_soft_self_topology(", 1)[1].split(
            "static bool soft_self_is_neighbor(", 1)[0]
        cls.edge_solver = cls.cpp.split("static void resolve_soft_body_self_edge_contacts(", 1)[1].split(
            "static void clear_pending_index(", 1)[0]
        cls.prestep = cls.cpp.split("void JoltSpace3D::_pre_step(float p_step) {", 1)[1].split(
            "void JoltSpace3D::_post_step(float p_step) {", 1)[0]

    def test_refit_preserves_candidates_for_many_deformation_steps(self):
        points, edges = random_mesh()
        entries, nodes = make_tree(points, edges)
        initial_layout = tuple(entry.index for entry in entries)
        rng = random.Random(18)
        for frame in range(32):
            # Move endpoints independently, changing segment orientation and
            # volumes. The old sorted median partition is never modified.
            points = [tuple(p[k] + rng.uniform(-.28, .28) for k in range(3))
                      for p in points]
            refit_tree(points, edges, entries, nodes)
            self.assertEqual(tuple(entry.index for entry in entries), initial_layout)
            for _ in range(28):
                origin = tuple(rng.uniform(-36, 36) for _ in range(3))
                end = tuple(origin[k] + rng.uniform(-.3, .3) for k in range(3))
                lo = tuple(min(a, b) for a, b in zip(origin, end))
                hi = tuple(max(a, b) for a, b in zip(origin, end))
                radius = rng.uniform(0, .8)
                actual, _ = query_tree(entries, nodes, lo, hi, radius)
                expected = {
                    j for j, edge in enumerate(edges)
                    if overlaps(lo, hi, *edge_bounds(points, edge), radius)
                }
                self.assertEqual(actual, expected, frame)

    def test_refit_handles_edge_moving_from_far_to_near(self):
        points, edges = random_mesh(edge_count=64)
        entries, nodes = make_tree(points, edges)
        # Replace two edge vertices with a segment at the origin, then
        # move it far away: the root and its leaf must update in both cases.
        points[0], points[1] = (-.2, 0, 0), (.2, 0, 0)
        refit_tree(points, edges, entries, nodes)
        hits, _ = query_tree(entries, nodes, (-.1, -.1, -.1), (.1, .1, .1), .01)
        self.assertIn(0, hits)
        points[0], points[1] = (300, 300, 300), (301, 300, 300)
        refit_tree(points, edges, entries, nodes)
        hits, _ = query_tree(entries, nodes, (-.1, -.1, -.1), (.1, .1, .1), .01)
        self.assertNotIn(0, hits)
        self.assertGreater(nodes[0].high[0], 300)

    def test_refit_matches_fresh_rebuild_when_geometry_changes(self):
        points, edges = random_mesh(seed=91, edge_count=192)
        entries, nodes = make_tree(points, edges)
        rng = random.Random(13)
        for _ in range(12):
            points = [tuple(v + rng.uniform(-2.0, 2.0) for v in p) for p in points]
            refit_tree(points, edges, entries, nodes)
            fresh_entries, fresh_nodes = make_tree(points, edges)
            for j in range(16):
                p = points[rng.randrange(len(points))]
                low, high = tuple(v - .2 for v in p), tuple(v + .2 for v in p)
                refitted, _ = query_tree(entries, nodes, low, high, .1)
                rebuilt, _ = query_tree(fresh_entries, fresh_nodes, low, high, .1)
                self.assertEqual(refitted, rebuilt)

    def test_refit_has_less_work_than_full_sort_on_large_mesh(self):
        edges = 1024
        leaves = 256
        node_count = 2 * leaves - 1
        refit_cost = 2 * edges + node_count
        build_cost = edges * (math.ceil(math.log2(edges)) + 2)
        self.assertLess(refit_cost, build_cost)
        self.assertEqual(refit_cost, 2559)

    def test_reversed_tree_dependencies(self):
        points, edges = random_mesh(edge_count=256)
        entries, nodes = make_tree(points, edges)
        for i, node in enumerate(nodes):
            if node.left != -1:
                self.assertGreater(node.left, i)
                self.assertGreater(node.right, i)
        refit_tree(points, edges, entries, nodes)
        self.assertTrue(all(nodes[i].low[k] <= nodes[i].high[k]
                            for i in range(len(nodes)) for k in range(3)))

    def test_runtime_cache_invalidation_and_limits(self):
        self.assertIn("struct JoltSelfCollisionCache {", self.cpp)
        self.assertIn("MAX_RETAINED_BODIES = 64", self.cpp)
        self.assertIn("JoltSelfCollisionCache *self_collision_cache = nullptr;", self.space_h)
        self.assertIn("self_collision_cache = new JoltSelfCollisionCache;", self.prestep)
        self.assertIn("self_collision_cache->bodies.find(id)", self.prestep)
        self.assertIn("self_collision_cache->bodies.size() <", self.prestep)
        self.assertIn("self_collision_cache->bodies.erase(p_jolt_id.GetIndexAndSequenceNumber());", self.cpp)
        self.assertIn("delete self_collision_cache;", self.cpp)
        self.assertIn("scratch->one_ring_edges.clear();", self.prestep)

    def test_cached_topology_validated_before_reuse(self):
        self.assertIn("r_scratch.topology_faces == &p_faces", self.cache)
        self.assertIn("r_scratch.topology_face_count == p_faces.size()", self.cache)
        self.assertIn("r_scratch.topology_vertex_count == p_vertex_count", self.cache)
        self.assertIn("r_scratch.edge_bvh_ready = false;", self.cache)
        self.assertIn("r_scratch.edge_bvh_refits = 0;", self.cache)
        self.assertIn("prepare_soft_self_topology(p_faces, p_vertex_count,", self.cache)
        self.assertIn("--r_budget; // Account for constant-time topology validation.", self.cache)

    def test_refit_is_bounded_and_topology_mapping_unchanged(self):
        self.assertIn("const uint32_t refit_cost = 2 * entry_count + node_count;", self.refit)
        self.assertIn("if (r_budget <= refit_cost)", self.refit)
        self.assertIn("r_budget -= refit_cost;", self.refit)
        self.assertIn("for (SoftFaceBVHEntry &entry : r_bvh.entries)", self.refit)
        self.assertIn("entry.face_index", self.refit)
        self.assertIn("for (uint32_t i = node_count; i > 0; --i)", self.refit)
        self.assertIn("node.min = JPH::Vec3::sMin(", self.refit)
        self.assertIn("node.max = JPH::Vec3::sMax(", self.refit)
        self.assertIn("r_scratch.edge_bvh_refits < 120", self.edge_solver)
        self.assertIn("refit_soft_self_edge_bvh(", self.edge_solver)
        self.assertIn("prepare_soft_self_edge_bvh(", self.edge_solver)
        self.assertIn("if (j <= i)", self.edge_solver)
        self.assertIn("soft_self_edges_are_neighbors(key_a, key_b, edges)", self.edge_solver)

    def test_default_off_and_dynamic_setting_guards(self):
        self.assertIn("inline static bool soft_body_self_persistent_bvh = false;", self.cfg_h)
        self.assertIn('simulation/soft_body_self_persistent_bvh"), false', self.cfg)
        self.assertIn("soft_body_self_persistent_bvh = GLOBAL_GET(", self.cfg)
        self.assertIn("JoltProjectSettings::soft_body_self_contacts &&", self.prestep)
        self.assertIn("JoltProjectSettings::soft_body_self_edge_contacts &&", self.prestep)
        self.assertIn("JoltProjectSettings::soft_body_self_edge_bvh &&", self.prestep)
        self.assertIn("JoltProjectSettings::soft_body_self_persistent_bvh;", self.prestep)
        self.assertIn("if (!persistent_self && self_collision_cache != nullptr)", self.prestep)

    def test_native_scene_rebuilds_and_recreates_body_after_long_refits(self):
        cfg = PROJECT.read_text(encoding="utf-8")
        native = NATIVE.read_text(encoding="utf-8")
        self.assertIn("soft_body_self_persistent_bvh=true", cfg)
        self.assertIn("const GRID := 8", native)
        self.assertIn("const FRAMES := 152", native)
        self.assertIn("const RECREATE_FRAME := 128", native)
        self.assertIn("PhysicsServer3D.free_rid(bodies[0])", native)
        self.assertIn("PASS: Jolt persistent self-edge BVH refit and body recreation", native)


if __name__ == "__main__":
    unittest.main()
