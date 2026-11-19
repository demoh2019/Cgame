"""Convex face clipping: validate signed-distance reuse and early-empty exit.

The production code uses Sutherland-Hodgman polygon clipping. This module
compares the original per-edge distance evaluation with the optimized
per-vertex distance cache on deterministic random polygons and planes.
The C++/GDScript engine tests must still be run on a compiled Cgame binary.
"""
from pathlib import Path
import math
import random
import re
import unittest


ROOT = Path(__file__).resolve().parents[2]
SAT = ROOT / "modules/godot_physics_3d/godot_collision_solver_3d_sat.cpp"
RUNTIME = ROOT / "tests/stress/physics_face_clip_3d_regression.gd"
WORKLOAD = ROOT / "tests/stress/physics_face_clip_3d.gd"
STRESS = ROOT / "tests/stress/stress.gd"
RUNNER = ROOT / "tests/stress/run.py"


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1]


def old_clip_polygon(points, planes):
    calls = 0
    clipbuf_src = list(points)
    for normal, d in planes:
        clipbuf_dst = []
        length = len(clipbuf_src)
        edge = length == 2
        for j in range(length):
            j_n = (j + 1) % length
            p0 = clipbuf_src[j]
            p1 = clipbuf_src[j_n]
            dist0 = dot(normal, p0) - d
            dist1 = dot(normal, p1) - d
            calls += 2
            if dist0 <= 0.0:
                clipbuf_dst.append(p0)
            if dist0 * dist1 < 0.0 and not (edge and j):
                rel = tuple(p1[k] - p0[k] for k in range(2))
                denominator = dot(normal, rel)
                fraction = -(dot(normal, p0) - d) / denominator
                clipbuf_dst.append(tuple(p0[k] + rel[k] * fraction for k in range(2)))
        clipbuf_src = clipbuf_dst
    return clipbuf_src, calls


def cached_clip_polygon(points, planes):
    calls = 0
    clipbuf_src = list(points)
    for normal, d in planes:
        length = len(clipbuf_src)
        if length == 0:
            return clipbuf_src, calls
        clipbuf_dst = []
        edge = length == 2
        first_clip_distance = dot(normal, clipbuf_src[0]) - d
        calls += 1
        dist0 = first_clip_distance
        for j in range(length):
            j_n = (j + 1) % length
            p0 = clipbuf_src[j]
            p1 = clipbuf_src[j_n]
            if j_n == 0:
                dist1 = first_clip_distance
            else:
                dist1 = dot(normal, p1) - d
                calls += 1
            if dist0 <= 0.0:
                clipbuf_dst.append(p0)
            if dist0 * dist1 < 0.0 and not (edge and j):
                rel = tuple(p1[k] - p0[k] for k in range(2))
                denominator = dot(normal, rel)
                fraction = -(dot(normal, p0) - d) / denominator
                clipbuf_dst.append(tuple(p0[k] + rel[k] * fraction for k in range(2)))
            dist0 = dist1
        clipbuf_src = clipbuf_dst
    return clipbuf_src, calls


class FaceClipDistanceCacheTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source = SAT.read_text(encoding="utf-8")
        start = source.index("static void _generate_contacts_face_face(")
        end = source.index("static void _generate_contacts_face_circle(", start)
        cls.code = source[start:end]

    def test_vertex_distance_cached_and_empty_polygon_exits(self):
        code = self.code
        self.assertIn("if (clipbuf_len == 0) {", code)
        self.assertIn("const real_t first_clip_distance = clip.distance_to(clipbuf_src[0]);", code)
        self.assertIn("real_t dist0 = first_clip_distance;", code)
        self.assertIn("const real_t dist1 = j_n == 0 ? first_clip_distance : clip.distance_to(edge1_A);", code)
        self.assertIn("dist0 = dist1;", code)
        self.assertIn("SWAP(clipbuf_src, clipbuf_dst);", code)
        self.assertLess(code.index("if (clipbuf_len == 0)"),
                        code.index("const real_t first_clip_distance"))
        self.assertIn("p_callback->call(clipbuf_src[i], closest_B, plane_B.get_normal());", code)
        # The old redundant first/last signed distance evaluation must stay gone.
        self.assertNotIn("real_t dist0 = clip.distance_to(edge0_A);", code)

    def test_10000_random_polygons_match_old_clipping(self):
        rng = random.Random(20261120)
        total_old = 0
        total_new = 0
        empty = 0
        for _ in range(10000):
            count = rng.randint(3, 16)
            center = (rng.uniform(-2.0, 2.0), rng.uniform(-2.0, 2.0))
            radius = rng.uniform(0.2, 3.0)
            phase = rng.uniform(-math.pi, math.pi)
            polygon = [
                (center[0] + radius * math.cos(phase + math.tau * i / count),
                 center[1] + radius * math.sin(phase + math.tau * i / count))
                for i in range(count)
            ]
            planes = []
            for _j in range(rng.randint(1, 8)):
                angle = rng.uniform(-math.pi, math.pi)
                normal = (math.cos(angle), math.sin(angle))
                d = rng.uniform(-3.0, 3.0)
                planes.append((normal, d))
            original, old_calls = old_clip_polygon(polygon, planes)
            cached, new_calls = cached_clip_polygon(polygon, planes)
            self.assertEqual(cached, original)
            self.assertLessEqual(new_calls, old_calls)
            total_old += old_calls
            total_new += new_calls
            if not cached:
                empty += 1
        self.assertGreater(empty, 0)
        self.assertGreater(total_old, total_new)

    def test_per_edge_distance_calls_are_halved_before_empty_exit(self):
        points = [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)]
        normal = (1.0, 0.0)
        for d in (2.0, 0.5, -0.5):
            original, calls_old = old_clip_polygon(points, [(normal, d)])
            updated, calls_new = cached_clip_polygon(points, [(normal, d)])
            self.assertEqual(original, updated)
            self.assertEqual(calls_old, 8)
            self.assertEqual(calls_new, 4)
        original, calls_old = old_clip_polygon(points, [(normal, -0.5), (normal, 0.5)])
        updated, calls_new = cached_clip_polygon(points, [(normal, -0.5), (normal, 0.5)])
        self.assertEqual(original, updated)
        self.assertEqual(calls_old, 8)
        self.assertEqual(calls_new, 4)

    def test_headless_regression_uses_many_sided_convex_hulls(self):
        script = RUNTIME.read_text(encoding="utf-8")
        self.assertIn("PhysicsServer3D.convex_polygon_shape_create()", script)
        self.assertIn("for i in range(12):", script)
        self.assertIn("for orientation in range(3):", script)
        self.assertIn("for margin in [0.0, 0.03]:", script)
        self.assertIn("state.intersect_shape(query, 16)", script)
        self.assertIn("state.collide_shape(query, 16)", script)
        self.assertIn("point.is_finite()", script)
        self.assertIn("PhysicsServer3D.free_rid(space)", script)

    def test_stress_is_registered_and_reports_frame_metrics(self):
        script = STRESS.read_text(encoding="utf-8")
        runner = RUNNER.read_text(encoding="utf-8")
        workload = WORKLOAD.read_text(encoding="utf-8")
        self.assertIn("func run(tree: SceneTree, scale: int, frames: int, rotated: bool)", workload)
        self.assertIn("var sides := 16", workload)
        self.assertIn("mini(256 * scale, 4096)", workload)
        self.assertIn('"frame_p95_ms": stats["p95"]', workload)
        self.assertIn('"peak_collision_pairs": peak_pairs', workload)
        for name, rotated in (("physics_face_clip_dense_3d", "false"),
                              ("physics_face_clip_rotated_3d", "true")):
            self.assertIn(f'"{name}"', runner)
            self.assertIn(f'"{name}":', script)
            self.assertIn(f"FaceClip3DStress.new().run(self, scale, frames, {rotated})", script)
        gd_cases = re.search(r"const CASES := \[([\s\S]*?)\]", script)
        py_cases = re.search(r"^CASES = \(([\s\S]*?)^\)", runner, re.MULTILINE)
        self.assertIsNotNone(gd_cases)
        self.assertIsNotNone(py_cases)
        cases_gd = re.findall(r'"([^"]+)"', gd_cases.group(1))
        cases_py = re.findall(r'"([^"]+)"', py_cases.group(1))
        self.assertEqual(cases_gd, cases_py)
        self.assertEqual(len(set(cases_gd)), len(cases_gd))


if __name__ == "__main__":
    unittest.main()
