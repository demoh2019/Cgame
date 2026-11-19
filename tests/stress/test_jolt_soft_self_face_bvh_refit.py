"""Reference geometry and source contracts for cached Cgame self-face BVH.

Run: python3 -m unittest tests/stress/test_jolt_soft_self_face_bvh_refit.py -v

This Python reference is independent of C++; it is NOT evidence that the
native physics editor compiled or that runtime latency improved.
"""
from dataclasses import dataclass
from pathlib import Path
import math
import random
import unittest

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "modules/jolt_physics/spaces/jolt_space_3d.cpp"
SETTINGS_H = ROOT / "modules/jolt_physics/jolt_project_settings.h"
SETTINGS_CPP = ROOT / "modules/jolt_physics/jolt_project_settings.cpp"
PROJECT = ROOT / "tests/stress/jolt_soft_self_face_bvh/project.godot"
SCENE = ROOT / "tests/stress/jolt_soft_self_face_bvh/persistent_face_bvh_regression.gd"


@dataclass
class Entry:
    face_index: int
    minimum: tuple
    maximum: tuple


@dataclass
class Node:
    minimum: tuple
    maximum: tuple
    begin: int
    end: int
    left: int = -1
    right: int = -1


def bounds(points, face):
    return (tuple(min(points[j][k] for j in face) for k in range(3)),
            tuple(max(points[j][k] for j in face) for k in range(3)))


def overlaps(point, low, high, radius):
    return all(low[k] - radius <= point[k] <= high[k] + radius for k in range(3))


def initial_tree(points, faces):
    entries = [Entry(i, *bounds(points, f)) for i, f in enumerate(faces)]
    nodes = []

    def build(begin, end):
        minimum = tuple(min(entry.minimum[k] for entry in entries[begin:end]) for k in range(3))
        maximum = tuple(max(entry.maximum[k] for entry in entries[begin:end]) for k in range(3))
        here = len(nodes)
        nodes.append(Node(minimum, maximum, begin, end))
        if end - begin <= 4:
            return here
        axis = max(range(3), key=lambda k: (maximum[k] - minimum[k], -k))
        mid = begin + (end - begin) // 2
        entries[begin:end] = sorted(entries[begin:end],
            key=lambda e: ((e.minimum[axis] + e.maximum[axis]) * .5, e.face_index))
        nodes[here].left = build(begin, mid)
        nodes[here].right = build(mid, end)
        return here

    if faces:
        build(0, len(faces))
    return entries, nodes


def refit(points, faces, entries, nodes):
    for entry in entries:
        entry.minimum, entry.maximum = bounds(points, faces[entry.face_index])
    for i in reversed(range(len(nodes))):
        node = nodes[i]
        if node.end - node.begin <= 4:
            node.minimum = tuple(min(e.minimum[k] for e in entries[node.begin:node.end]) for k in range(3))
            node.maximum = tuple(max(e.maximum[k] for e in entries[node.begin:node.end]) for k in range(3))
        else:
            left, right = nodes[node.left], nodes[node.right]
            node.minimum = tuple(min(left.minimum[k], right.minimum[k]) for k in range(3))
            node.maximum = tuple(max(left.maximum[k], right.maximum[k]) for k in range(3))


def query(point, entries, nodes, radius):
    found = set()
    visits = 0
    if not nodes:
        return found, visits
    stack = [0]
    while stack:
        node = nodes[stack.pop()]
        visits += 1
        if not overlaps(point, node.minimum, node.maximum, radius):
            continue
        if node.left < 0:
            for j in range(node.begin, node.end):
                entry = entries[j]
                if overlaps(point, entry.minimum, entry.maximum, radius):
                    found.add(entry.face_index)
        else:
            stack.extend([node.right, node.left])
    return found, visits


def sample(seed=42, face_count=256):
    rng = random.Random(seed)
    points, faces = [], []
    for _ in range(face_count):
        x, y, z = (rng.uniform(-20, 20) for _ in range(3))
        a = (x, y, z)
        b = (x + rng.uniform(.15, .65), y, z)
        c = (x, y + rng.uniform(.15, .65), z + rng.uniform(-.1, .1))
        start = len(points)
        points.extend([a, b, c])
        faces.append((start, start + 1, start + 2))
    return points, faces


class SelfFaceBVHRefitTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cpp = SOURCE.read_text(encoding="utf-8")
        cls.cfg_h = SETTINGS_H.read_text(encoding="utf-8")
        cls.cfg = SETTINGS_CPP.read_text(encoding="utf-8")
        cls.helper = cls.cpp.split("static bool refit_soft_self_face_bvh(", 1)[1].split(
            "static void resolve_soft_body_self_contacts(", 1)[0]
        cls.solver = cls.cpp.split("static void resolve_soft_body_self_contacts(", 1)[1].split(
            "static bool soft_self_edges_are_neighbors(", 1)[0]
        cls.pre = cls.cpp.split("void JoltSpace3D::_pre_step(float p_step) {", 1)[1].split(
            "void JoltSpace3D::_post_step(float p_step) {", 1)[0]

    def test_randomized_deformation_queries_equal_full_scan(self):
        points, faces = sample()
        entries, nodes = initial_tree(points, faces)
        original = [e.face_index for e in entries]
        rng = random.Random(51)
        total = 0
        for frame in range(26):
            points = [tuple(v + rng.uniform(-.3, .3) for v in p) for p in points]
            refit(points, faces, entries, nodes)
            self.assertEqual([e.face_index for e in entries], original)
            for _ in range(45):
                center = tuple(rng.uniform(-21, 21) for _ in range(3))
                radius = rng.uniform(0, .9)
                found, _ = query(center, entries, nodes, radius)
                brute = {i for i, face in enumerate(faces)
                         if overlaps(center, *bounds(points, face), radius)}
                self.assertEqual(found, brute)
                total += 1
        self.assertEqual(total, 1170)

    def test_queries_match_fresh_rebuild_after_large_folds(self):
        points, faces = sample(13, face_count=128)
        entries, nodes = initial_tree(points, faces)
        rng = random.Random(25)
        for _ in range(12):
            points = [tuple(x + rng.uniform(-3, 3) for x in p) for p in points]
            refit(points, faces, entries, nodes)
            rebuilt_entries, rebuilt_nodes = initial_tree(points, faces)
            for _ in range(24):
                pivot = points[rng.randrange(len(points))]
                lo = tuple(x + rng.uniform(-.2, .2) for x in pivot)
                self.assertEqual(query(lo, entries, nodes, .15)[0],
                                 query(lo, rebuilt_entries, rebuilt_nodes, .15)[0])

    def test_teleporting_triangle_cannot_leave_stale_aabb(self):
        points, faces = sample(4, 64)
        entries, nodes = initial_tree(points, faces)
        for i in faces[0]:
            points[i] = (300 + float(i), 301., 302.)
        refit(points, faces, entries, nodes)
        nearest = query((300.7, 301., 302.), entries, nodes, 2.)[0]
        self.assertIn(0, nearest)
        self.assertGreater(nodes[0].maximum[0], 300)
        for i in faces[0]:
            points[i] = (500 + float(i), 501., 502.)
        refit(points, faces, entries, nodes)
        self.assertNotIn(0, query((300.7, 301., 302.), entries, nodes, 2.)[0])

    def test_reverse_node_order_matches_construction_dependencies(self):
        points, faces = sample(1, 768)
        entries, nodes = initial_tree(points, faces)
        self.assertLessEqual(len(nodes), 2*len(faces))
        for i, node in enumerate(nodes):
            if node.left >= 0:
                self.assertGreater(node.left, i)
                self.assertGreater(node.right, i)
        refit(points, faces, entries, nodes)
        self.assertTrue(all(n.minimum[k] <= n.maximum[k] for n in nodes for k in range(3)))

    def test_refit_work_is_bounded_and_below_median_rebuild_cost(self):
        for face_count in (64, 128, 256, 512, 1024):
            points, faces = sample(3, face_count)
            entries, nodes = initial_tree(points, faces)
            work = 4 * len(entries) + len(nodes)
            levels = math.ceil(math.log2(face_count))
            build = face_count * (levels + 1)
            self.assertLess(work, build)

    def test_default_off_and_independent_of_edge_mode(self):
        self.assertIn("inline static bool soft_body_self_face_bvh_refit = false;", self.cfg_h)
        self.assertIn('simulation/soft_body_self_face_bvh_refit"), false', self.cfg)
        self.assertIn("soft_body_self_face_bvh_refit = GLOBAL_GET(", self.cfg)
        self.assertIn("JoltProjectSettings::soft_body_self_face_bvh_refit", self.solver)
        self.assertIn("JoltProjectSettings::soft_body_self_face_bvh_refit);", self.pre)
        self.assertIn("const bool persistent_edges", self.pre)
        self.assertIn("const bool persistent_self = persistent_edges ||", self.pre)

    def test_cache_and_topology_lifecycle(self):
        self.assertIn("face_bvh_face_count = 0", self.cpp)
        self.assertIn("face_bvh_refits = 0", self.cpp)
        self.assertIn("face_bvh_ready = false", self.cpp)
        self.assertIn("r_scratch.face_bvh_ready = false;", self.cpp)
        self.assertIn("r_scratch.edge_bvh_ready = false;", self.cpp)
        self.assertIn("self_collision_cache->bodies.erase(p_jolt_id.GetIndexAndSequenceNumber());", self.cpp)
        self.assertIn("MAX_RETAINED_BODIES = 64", self.cpp)
        self.assertIn("if (!persistent_self && self_collision_cache != nullptr)", self.pre)

    def test_refit_work_and_validity_guards(self):
        self.assertIn("const uint32_t refit_cost = 4 * entry_count + node_count;", self.helper)
        self.assertIn("if (r_budget <= refit_cost)", self.helper)
        self.assertIn("r_budget -= refit_cost;", self.helper)
        self.assertIn("if (entry.face_index >= p_faces.size())", self.helper)
        self.assertIn("face.IsDegenerate()", self.helper)
        self.assertIn("!Math::is_finite(entry.min.GetX())", self.helper)
        self.assertIn("!Math::is_finite(entry.max.GetZ())", self.helper)
        self.assertIn("for (uint32_t i = node_count; i > 0; --i)", self.helper)
        self.assertIn("node.min = JPH::Vec3::sMin(", self.helper)
        self.assertIn("node.max = JPH::Vec3::sMax(", self.helper)

    def test_solver_refits_and_rebuilds_without_stale_nodes(self):
        self.assertIn("const bool refit_faces = JoltProjectSettings::soft_body_self_face_bvh_refit;", self.solver)
        self.assertIn("r_scratch.face_bvh_refits < 120", self.solver)
        self.assertIn("refit_soft_self_face_bvh(faces, vertices, r_scratch.bvh, r_budget)", self.solver)
        self.assertIn("r_scratch.bvh.clear();", self.solver)
        self.assertIn("prepare_soft_face_bvh(faces, vertices, JPH::Quat::sIdentity()", self.solver)
        self.assertIn("r_scratch.face_bvh_ready = use_bvh;", self.solver)
        self.assertIn("r_scratch.face_bvh_face_count = use_bvh ?", self.solver)
        self.assertIn("const bool needs_bvh = faces.size() >= MIN_SOFT_FACE_BVH_FACES;", self.solver)
        self.assertIn("if (needs_bvh && !use_bvh)", self.solver)
        self.assertIn("soft_self_is_neighbor(i, face, r_scratch.one_ring_edges)", self.solver)
        self.assertIn("predict_soft_self_vertex_face_sweep(", self.solver)
        self.assertIn("if (!swept_contact && r_scratch.position_projection_ready)", self.solver)

    def test_native_scene_uses_face_only_and_eviction(self):
        cfg = PROJECT.read_text(encoding="utf-8")
        native = SCENE.read_text(encoding="utf-8")
        self.assertIn("soft_body_self_face_bvh_refit=true", cfg)
        self.assertIn("soft_body_self_edge_contacts=false", cfg)
        self.assertIn("soft_body_self_persistent_bvh=false", cfg)
        self.assertIn("const FRAMES := 152", native)
        self.assertIn("const RECREATE_FRAME := 128", native)
        self.assertIn("PhysicsServer3D.free_rid(bodies[0])", native)
        self.assertIn("PASS: Jolt persistent self-face BVH refit and body recreation", native)


if __name__ == "__main__":
    unittest.main()
