"""Conservative edge BVH reference tests for deforming Jolt self-collision.

Run with: python3 -m unittest tests/stress/test_jolt_soft_self_edge_bvh.py -v
This tests broadphase geometry/source contracts, NOT native C++ execution.
"""
from dataclasses import dataclass
import math
from pathlib import Path
import random
import unittest

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "modules/jolt_physics/spaces/jolt_space_3d.cpp"
HEADER = ROOT / "modules/jolt_physics/jolt_project_settings.h"
CONFIG = ROOT / "modules/jolt_physics/jolt_project_settings.cpp"
PROJECT = ROOT / "tests/stress/jolt_soft_self_edge_bvh/project.godot"
NATIVE = ROOT / "tests/stress/jolt_soft_self_edge_bvh/bvh_self_edges_regression.gd"


@dataclass
class Entry:
    edge_index: int
    lo: tuple
    hi: tuple


@dataclass
class Node:
    lo: tuple
    hi: tuple
    begin: int
    end: int
    left: object = None
    right: object = None


def bounds(segment):
    return (
        tuple(min(segment[0][i], segment[1][i]) for i in range(3)),
        tuple(max(segment[0][i], segment[1][i]) for i in range(3)),
    )


def overlaps(a_lo, a_hi, b_lo, b_hi, radius):
    return all(a_hi[i] + radius >= b_lo[i] and b_hi[i] + radius >= a_lo[i]
               for i in range(3))


def build(entries, begin=0, end=None, leaf_size=4):
    """Median hierarchy with original edge-index provenance."""
    if end is None:
        end = len(entries)
    lo = tuple(min(e.lo[k] for e in entries[begin:end]) for k in range(3))
    hi = tuple(max(e.hi[k] for e in entries[begin:end]) for k in range(3))
    node = Node(lo, hi, begin, end)
    if end - begin <= leaf_size:
        return node
    axis = max(range(3), key=lambda k: (hi[k] - lo[k], -k))
    entries[begin:end] = sorted(entries[begin:end],
                                key=lambda entry: (0.5 * (entry.lo[axis] + entry.hi[axis]),
                                                   entry.edge_index))
    middle = begin + (end - begin) // 2
    node.left = build(entries, begin, middle, leaf_size)
    node.right = build(entries, middle, end, leaf_size)
    return node


def query(root, entries, lo, hi, radius, budget=65536):
    """Return candidate indices and tree-node work (not exact narrowphase)."""
    hits = []
    stack = [root]
    visited = 0
    while stack and visited < budget:
        node = stack.pop()
        visited += 1
        if not overlaps(lo, hi, node.lo, node.hi, radius):
            continue
        if node.left is not None:
            stack.extend([node.right, node.left])
        else:
            for index in range(node.begin, node.end):
                entry = entries[index]
                if overlaps(lo, hi, entry.lo, entry.hi, radius):
                    hits.append(entry.edge_index)
    return hits, visited


def random_edges(seed=23, count=256, scale=40):
    rng = random.Random(seed)
    edges = []
    for index in range(count):
        p0 = tuple(rng.uniform(-scale, scale) for _ in range(3))
        p1 = tuple(p0[k] + rng.uniform(-.4, .4) for k in range(3))
        edges.append((p0, p1))
    return edges


def make_entries(segments):
    result = []
    for index, segment in enumerate(segments):
        if not all(math.isfinite(x) for point in segment for x in point):
            continue
        lo, hi = bounds(segment)
        result.append(Entry(index, lo, hi))
    return result


class SelfEdgeBVHReferenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cpp = SOURCE.read_text(encoding="utf-8")
        cls.header = HEADER.read_text(encoding="utf-8")
        cls.config = CONFIG.read_text(encoding="utf-8")
        cls.prepare = cls.cpp.split("static bool prepare_soft_self_edge_bvh(", 1)[1].split(
            "static bool soft_self_edge_bounds_overlap(", 1
        )[0]
        cls.query_code = cls.cpp.split("static void query_soft_self_edge_bvh(", 1)[1].split(
            "static void resolve_soft_body_self_edge_contacts(", 1
        )[0]
        cls.solver = cls.cpp.split("static void resolve_soft_body_self_edge_contacts(", 1)[1].split(
            "static void clear_pending_index(", 1
        )[0]

    def test_identical_candidate_sets_to_linear_scan_on_random_edges(self):
        segments = random_edges()
        entries = make_entries(segments)
        nodes = build(entries)
        rng = random.Random(87)
        for _ in range(900):
            p0 = tuple(rng.uniform(-41, 41) for _ in range(3))
            p1 = tuple(p0[k] + rng.uniform(-.5, .5) for k in range(3))
            lo, hi = bounds((p0, p1))
            radius = rng.uniform(0, 1)
            accelerated, _ = query(nodes, entries, lo, hi, radius)
            expected = {entry.edge_index for entry in entries
                        if overlaps(lo, hi, entry.lo, entry.hi, radius)}
            self.assertEqual(set(accelerated), expected)

    def test_touching_boundary_and_sparse_crossing(self):
        segments = [
            ((-.9, 2, 0), (.9, 2, 0)),
            ((0, 1.1, 0), (0, 2.9, 0)),
            ((4, 0, 0), (5, 0, 0)),
            ((0, 2.15, 0), (0, 3, 0)),
        ]
        entries = make_entries(segments)
        tree = build(entries, leaf_size=1)
        for point, radius, expected in [
            (0, .0, {0, 1}), (0, .15, {0, 1, 3}),
            (1, 0., {0, 1, 3}), (2, .0, {2}),
        ]:
            lo, hi = bounds(segments[point])
            hits, _ = query(tree, entries, lo, hi, radius)
            self.assertEqual(set(hits), expected)

    def test_original_edge_order_survives_median_partition(self):
        segments = random_edges(seed=11, count=128)
        entries = make_entries(segments)
        root = build(entries)
        self.assertEqual(sorted(e.edge_index for e in entries), list(range(128)))
        # Keep j>i, regardless of reordered tree leaves.
        for i, segment in enumerate(segments):
            lo, hi = bounds(segment)
            accelerated = {j for j in query(root, entries, lo, hi, .2)[0] if j > i}
            brute = {j for j in range(i+1, len(segments))
                     if overlaps(lo, hi, *bounds(segments[j]), .2)}
            self.assertEqual(accelerated, brute)

    def test_structure_and_bounded_depth(self):
        edges = random_edges(count=1024)
        entries = make_entries(edges)
        root = build(entries)
        stack = [(root, 1)]
        maximum = 0
        while stack:
            node, depth = stack.pop()
            maximum = max(maximum, depth)
            if node.left is not None:
                stack.extend([(node.left, depth+1), (node.right, depth+1)])
            else:
                self.assertLessEqual(node.end-node.begin, 4)
        self.assertLessEqual(maximum, 9)

    def test_distant_edges_reduce_candidate_and_node_visits(self):
        edges = random_edges(count=512)
        entries = make_entries(edges)
        root = build(entries)
        rng = random.Random(9)
        total_work = 0
        for _ in range(250):
            x = tuple(rng.uniform(-40, 40) for _ in range(3))
            y = tuple(x[k] + rng.uniform(-.2, .2) for k in range(3))
            lo, hi = bounds((x, y))
            result, visits = query(root, entries, lo, hi, .15)
            total_work += visits + len(result)
        self.assertLess(total_work, 250 * len(edges) // 5)

    def test_nonfinite_segments_are_removed_from_tree(self):
        edges = random_edges(count=80)
        edges[13] = ((float("nan"), 0, 0), (0, 1, 0))
        edges[17] = ((1, 0, 0), (1, 0, float("inf")))
        entries = make_entries(edges)
        self.assertEqual(len(entries), 78)
        root = build(entries)
        self.assertEqual(query(root, entries, (0, 0, 0), (0, 0, 0), .1)[0],
                         [e.edge_index for e in entries if overlaps((0, 0, 0), (0, 0, 0), e.lo, e.hi, .1)])

    def test_opt_in_setting_preserves_linear_default(self):
        self.assertIn("inline static bool soft_body_self_edge_bvh = false;", self.header)
        self.assertIn('simulation/soft_body_self_edge_bvh"), false', self.config)
        self.assertIn("soft_body_self_edge_bvh = GLOBAL_GET(", self.config)
        self.assertIn("JoltProjectSettings::soft_body_self_edge_bvh &&", self.solver)
        self.assertIn("const bool use_edge_bvh", self.solver)
        self.assertIn("const uint32_t candidate_count = use_edge_bvh ?", self.solver)
        self.assertIn("const uint32_t j = use_edge_bvh ?", self.solver)
        self.assertIn("if (j <= i)", self.solver)
        self.assertIn("soft_self_edges_are_neighbors(key_a, key_b, edges)", self.solver)

    def test_bounded_build_traversal_and_candidate_debits(self):
        self.assertIn("MIN_SOFT_SELF_EDGE_BVH_EDGES = 32", self.cpp)
        self.assertIn("MAX_SOFT_SELF_EDGE_BVH_EDGES = 3072", self.cpp)
        self.assertIn("const uint32_t build_cost = edge_count * (levels + 2)", self.prepare)
        self.assertIn("if (r_budget <= build_cost)", self.prepare)
        self.assertIn("r_budget -= build_cost;", self.prepare)
        self.assertIn("build_soft_face_bvh(r_bvh.entries,", self.prepare)
        self.assertIn("r_bvh.stack.reserve(32)", self.prepare)
        self.assertIn("while (!r_bvh.stack.empty() && r_budget > 0)", self.query_code)
        self.assertIn("--r_budget; // Every visited node", self.query_code)
        self.assertIn("--r_budget; // Every tested candidate", self.solver)
        self.assertIn("if (!soft_self_edge_bounds_overlap(", self.solver)

    def test_scratch_arrays_are_reused_between_soft_bodies(self):
        self.assertIn("SoftFaceBVHScratch edge_bvh; // Reused across active soft bodies.", self.cpp)
        self.assertIn("r_bvh.clear();", self.prepare)
        self.assertIn("r_bvh.entries.reserve(edge_count);", self.prepare)
        self.assertIn("r_bvh.nodes.reserve(2 * r_bvh.entries.size());", self.prepare)
        self.assertIn("r_bvh.candidates.clear();", self.query_code)
        self.assertIn("r_bvh.stack.clear();", self.query_code)
        self.assertIn("SoftSelfContactScratch self_scratch;", self.cpp)

    def test_native_scene_uses_dense_self_intersecting_panels(self):
        config = PROJECT.read_text(encoding="utf-8")
        scene = NATIVE.read_text(encoding="utf-8")
        self.assertIn("soft_body_self_contacts=true", config)
        self.assertIn("soft_body_self_edge_contacts=true", config)
        self.assertIn("soft_body_self_edge_bvh=true", config)
        self.assertIn("const GRID := 8", scene)
        self.assertIn("PASS: Jolt BVH accelerated self edge collisions", scene)


if __name__ == "__main__":
    unittest.main()
