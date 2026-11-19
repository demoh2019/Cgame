"""Barycentric soft-body contact BVH: conservative broadphase reference tests.

This Python test verifies the AABB tree candidate contract. Native Jolt
simulation is tested separately using jolt_soft_soft_bvh/bvh_regression.gd.
"""
from dataclasses import dataclass
import math
from pathlib import Path
import random
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPACE = (ROOT / "modules/jolt_physics/spaces/jolt_space_3d.cpp")
CONFIG = (ROOT / "modules/jolt_physics/jolt_project_settings.cpp")
HEADER = (ROOT / "modules/jolt_physics/jolt_project_settings.h")
PROJECT = (ROOT / "tests/stress/jolt_soft_soft_bvh/project.godot")
NATIVE = (ROOT / "tests/stress/jolt_soft_soft_bvh/bvh_regression.gd")


@dataclass
class Entry:
    idx: int
    lo: tuple
    hi: tuple


@dataclass
class Node:
    lo: tuple
    hi: tuple
    left: object = None
    right: object = None
    entries: tuple = ()


def valid_face(vertices):
    if not all(math.isfinite(x) for v in vertices for x in v):
        return False
    a, b, c = vertices
    ab = [b[i] - a[i] for i in range(3)]
    ac = [c[i] - a[i] for i in range(3)]
    cross = (ab[1] * ac[2] - ab[2] * ac[1],
             ab[2] * ac[0] - ab[0] * ac[2],
             ab[0] * ac[1] - ab[1] * ac[0])
    return sum(x * x for x in cross) > 1e-14


def bounds(points):
    return (tuple(min(p[i] for p in points) for i in range(3)),
            tuple(max(p[i] for p in points) for i in range(3)))


def index_faces(faces):
    result = []
    for idx, face in enumerate(faces):
        if not valid_face(face):
            continue
        lo, hi = bounds(face)
        result.append(Entry(idx, lo, hi))
    return result


def build(entries, leaf_size=4):
    assert entries
    lo = tuple(min(e.lo[i] for e in entries) for i in range(3))
    hi = tuple(max(e.hi[i] for e in entries) for i in range(3))
    if len(entries) <= leaf_size:
        return Node(lo, hi, entries=tuple(entries))
    axis = max(range(3), key=lambda i: (hi[i] - lo[i], -i))
    sorted_entries = sorted(entries, key=lambda e:
                            (0.5 * e.lo[axis] + 0.5 * e.hi[axis], e.idx))
    mid = len(sorted_entries) // 2
    return Node(lo, hi, left=build(sorted_entries[:mid], leaf_size),
                right=build(sorted_entries[mid:], leaf_size))


def overlaps(lo, hi, point, radius):
    return all(lo[i] - radius <= point[i] <= hi[i] + radius for i in range(3))


def query(root, point, radius):
    results = set()
    stack = [root]
    nodes_visited = 0
    while stack:
        node = stack.pop()
        nodes_visited += 1
        if not overlaps(node.lo, node.hi, point, radius):
            continue
        if node.left is None:
            for e in node.entries:
                if overlaps(e.lo, e.hi, point, radius):
                    results.add(e.idx)
        else:
            stack.extend((node.right, node.left))
    return results, nodes_visited


def make_faces(seed=7, count=240):
    rng = random.Random(seed)
    result = []
    for i in range(count):
        x, y, z = (rng.uniform(-50, 50) for _ in range(3))
        w = rng.uniform(0.05, 0.8)
        result.append(((x, y, z), (x + w, y + 0.1 * w, z),
                       (x, y + w, z + 0.3 * w)))
    return result


class JoltSoftFaceBVHTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.code = SPACE.read_text(encoding="utf-8")
        cls.config = CONFIG.read_text(encoding="utf-8")
        cls.header = HEADER.read_text(encoding="utf-8")

    def test_no_false_negatives_against_linear_aabb(self):
        faces = make_faces()
        entries = index_faces(faces)
        root = build(entries)
        rng = random.Random(99)
        for _ in range(600):
            q = tuple(rng.uniform(-51, 51) for _ in range(3))
            radius = rng.uniform(0, 1.0)
            accelerated, _ = query(root, q, radius)
            linear = {e.idx for e in entries if overlaps(e.lo, e.hi, q, radius)}
            self.assertEqual(accelerated, linear)

    def test_detects_thin_and_boundary_faces(self):
        faces = [((-1.0, 0, -1.0), (1.0, 0, -1.0), (0, 0, 1.0)),
                 ((4, -1, -1), (4, 1, -1), (4, 0, 1))]
        root = build(index_faces(faces), 1)
        for point, radius, expected in [
            ((0, 0.09, 0), 0.1, {0}),
            ((4.1, 0, 0), 0.11, {1}),
            ((2, 2, 2), 0.1, set()),
            ((1.1, 0, -1), 0.1, {0}),
        ]:
            self.assertEqual(query(root, point, radius)[0], expected)

    def test_skips_nonfinite_and_degenerate_triangles(self):
        faces = make_faces(count=40)
        faces[3] = ((0, 0, 0), (1, 0, 0), (2, 0, 0))
        faces[6] = ((0, 0, 0), (float("nan"), 0, 0), (1, 0, 0))
        entries = index_faces(faces)
        self.assertEqual(len(entries), 38)
        self.assertNotIn(3, [entry.idx for entry in entries])
        self.assertNotIn(6, [entry.idx for entry in entries])
        self.assertEqual(query(build(entries), (0, 0, 0), 0.1)[0],
                         {e.idx for e in entries if overlaps(e.lo, e.hi, (0, 0, 0), 0.1)})

    def test_structural_depth_and_candidate_savings(self):
        faces = make_faces(count=512)
        entries = index_faces(faces)
        root = build(entries)
        max_depth = 0
        stack = [(root, 1)]
        while stack:
            node, depth = stack.pop()
            max_depth = max(max_depth, depth)
            if node.left is not None:
                stack.extend(((node.left, depth + 1), (node.right, depth + 1)))
            else:
                self.assertLessEqual(len(node.entries), 4)
        self.assertLessEqual(max_depth, 9)
        rng = random.Random(104)
        visits = 0
        candidates = 0
        for _ in range(200):
            point = tuple(rng.uniform(-50, 50) for _ in range(3))
            candidates_one, count = query(root, point, 0.3)
            candidates += len(candidates_one)
            visits += count
        self.assertLess(visits + candidates, 200 * len(faces) // 4)

    def test_hierarchy_source_contract_and_default_off(self):
        self.assertIn("inline static bool soft_body_soft_vertex_face_bvh = false;", self.header)
        self.assertIn('simulation/soft_body_soft_vertex_face_bvh"), false', self.config)
        self.assertIn("static uint32_t build_soft_face_bvh(", self.code)
        self.assertIn("std::nth_element(", self.code)
        self.assertIn("MAX_SOFT_FACE_BVH_FACES = 4096", self.code)
        self.assertIn("SOFT_FACE_BVH_LEAF_SIZE = 4", self.code)
        self.assertIn("face_candidates.reserve(face_entries.size());", self.code)

    def test_global_budget_charged_for_build_traversal_and_exact_tests(self):
        self.assertIn("const uint32_t build_cost = (uint32_t)p_faces.size() * (split_levels + 1)", self.code)
        self.assertIn("r_budget -= build_cost;", self.code)
        self.assertIn("--r_budget;", self.code)
        self.assertIn("--r_contact_budget; // Every exact face test", self.code)
        self.assertIn("if (r_contact_budget == 0)", self.code)
        self.assertIn("if (r_budget <= build_cost)", self.code)

    def test_moving_faces_are_refit_each_query_and_both_directions(self):
        self.assertIn("prepare_soft_face_bvh(faces, face_vertices, face_rotation, face_relative_to_point", self.code)
        self.assertIn("p_rotation * p_vertices[face.mVertex[0]].mPosition", self.code)
        self.assertIn("resolve_soft_soft_vertex_face_direction(p_body_a, p_body_b", self.code)
        self.assertIn("resolve_soft_soft_vertex_face_direction(p_body_b, p_body_a", self.code)
        self.assertIn("JoltProjectSettings::soft_body_soft_vertex_face_bvh &&", self.code)
        self.assertIn("resolve_soft_soft_particle_contacts(*jolt_a, *jolt_b", self.code)

    def test_native_scene_uses_dense_surface_for_bvh(self):
        config = PROJECT.read_text(encoding="utf-8")
        scene = NATIVE.read_text(encoding="utf-8")
        self.assertIn("soft_body_soft_vertex_face_bvh=true", config)
        self.assertIn("const GRID := 8", scene)
        self.assertIn("allowed_lift", scene)
        self.assertIn("masked_lift", scene)
        self.assertIn("PASS: Jolt bounded BVH soft-soft vertex-face contacts", scene)


if __name__ == "__main__":
    unittest.main()
