"""Box2D-style analytic manifold for circles with identical centers.

Verify the legacy SAT-equivalent fallback normal, arbitrary valid cached
axes, exact overlap logic and stress runner registration. Actual GDScript
queries and rigid-body response are checked by the headless companion test.
"""
from pathlib import Path
import math
import random
import re
import unittest


ROOT = Path(__file__).resolve().parents[2]
SAT = ROOT / "modules/godot_physics_2d/godot_collision_solver_2d_sat.cpp"
RUNTIME = ROOT / "tests/stress/physics_coincident_circles_2d_regression.gd"
STRESS_CASE = ROOT / "tests/stress/physics_coincident_circles_2d.gd"
REGISTRY_GD = ROOT / "tests/stress/stress.gd"
REGISTRY_PY = ROOT / "tests/stress/run.py"


def coincident_circle_manifold(radius_a, radius_b, cached_axis=None):
    # The old zero-vector SAT substituted +Y for its candidate axis,
    # then selected -Y as its best axis for equal interval depths.
    if cached_axis is None or math.hypot(*cached_axis) < 1.0e-6:
        axis = (0.0, -1.0)
    else:
        size = math.hypot(*cached_axis)
        axis = (-cached_axis[0] / size, -cached_axis[1] / size)
    point_a = (-axis[0] * radius_a, -axis[1] * radius_a)
    point_b = (axis[0] * radius_b, axis[1] * radius_b)
    return axis, point_a, point_b


class CoincidentCircleContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        content = SAT.read_text(encoding="utf-8")
        begin = content.index("static void _collision_circle_circle(")
        end = content.index("static void _collision_circle_rectangle(", begin)
        cls.code = content[begin:end]

    def test_analytic_manifold_accepts_only_real_nonnegative_effective_radii(self):
        code = self.code
        self.assertIn("!p_cast_A && !p_cast_B", code)
        self.assertIn("_is_unit_orthogonal_transform(p_transform_a)", code)
        self.assertIn("_is_unit_orthogonal_transform(p_transform_b)", code)
        self.assertIn("radius_A >= 0.0 && radius_B >= 0.0", code)
        self.assertIn("(distance_squared > 0.0 || combined_radius > 0.0)", code)
        self.assertIn("if (distance_squared > combined_radius * combined_radius)", code)
        self.assertIn("p_collector->collided = true;", code)

    def test_cached_separator_and_legacy_y_fallback(self):
        code = self.code
        self.assertIn("Box2D-style coincident-circle manifold", code)
        self.assertIn("if (distance_squared > 0.0) {", code)
        self.assertIn("axis = Vector2(0.0, -1.0);", code)
        self.assertIn("(*p_collector->sep_axis).is_finite()", code)
        self.assertIn("cached_length_squared > real_t(CMP_EPSILON) * real_t(CMP_EPSILON)", code)
        self.assertIn("axis = -cached_axis / Math::sqrt(cached_length_squared);", code)
        self.assertIn("p_collector->normal = axis;", code)
        self.assertIn("p_transform_a.get_origin() - axis * radius_A", code)
        self.assertIn("p_transform_b.get_origin() + axis * radius_B", code)
        self.assertIn("*p_collector->sep_axis = Vector2();", code)
        self.assertIn("SeparatorAxisTest2D<GodotCircleShape2D, GodotCircleShape2D>", code)
        self.assertIn("separator.generate_contacts();", code)

    def test_10000_positive_radii_produce_finite_separating_contacts(self):
        rng = random.Random(20261119)
        for _ in range(10000):
            r_a = rng.uniform(0.01, 10.0)
            r_b = rng.uniform(0.01, 10.0)
            axis_in = (rng.uniform(-5.0, 5.0), rng.uniform(-5.0, 5.0))
            axis, point_a, point_b = coincident_circle_manifold(r_a, r_b, axis_in)
            self.assertAlmostEqual(math.hypot(*axis), 1.0, places=12)
            self.assertTrue(all(math.isfinite(v) for v in point_a + point_b))
            # The normal points along the support pair's A->B direction.
            gap = (point_b[0] - point_a[0], point_b[1] - point_a[1])
            self.assertAlmostEqual(sum(gap[i] * axis[i] for i in range(2)), r_a + r_b, places=10)
            # A rigid pair uses the opposite impulse direction on A.
            self.assertAlmostEqual(sum((-axis[i]) * (-gap[i]) for i in range(2)),
                                   r_a + r_b, places=10)

    def test_zero_axis_matches_old_sat_y_contact(self):
        for r_a, r_b in ((1.0, 1.0), (0.25, 2.0), (10.0, 0.1)):
            axis, a, b = coincident_circle_manifold(r_a, r_b)
            self.assertEqual(axis, (0.0, -1.0))
            self.assertEqual(a, (0.0, r_a))
            self.assertEqual(b, (0.0, -r_b))
            # Cached +X was previously evaluated before the default +Y.
            cached_axis, _, _ = coincident_circle_manifold(r_a, r_b, (1.0, 0.0))
            self.assertEqual(cached_axis, (-1.0, 0.0))

    def test_runtime_covers_overlap_fallback_and_rigid_sep(self):
        code = RUNTIME.read_text(encoding="utf-8")
        self.assertIn("for mode in range(3):", code)
        self.assertIn("Vector2.ZERO, \"hit\": true", code)
        self.assertIn("transform.scaled_local(Vector2(1.5, 1.0))", code)
        self.assertIn("state.intersect_shape(query, 8)", code)
        self.assertIn("state.collide_shape(query, 8)", code)
        self.assertIn("point.is_finite()", code)
        self.assertIn("for frame in range(36):", code)
        self.assertIn("pose.origin.length_squared() < 0.0001", code)
        self.assertIn("PhysicsServer2D.free_rid(space)", code)

    def test_benchmark_registration_and_metrics(self):
        script = STRESS_CASE.read_text(encoding="utf-8")
        gd = REGISTRY_GD.read_text(encoding="utf-8")
        py = REGISTRY_PY.read_text(encoding="utf-8")
        self.assertIn("func run(tree: SceneTree, scale: int, frames: int, coincident: bool)", script)
        self.assertIn("mini(256 * scale, 4096)", script)
        self.assertIn('"frame_p95_ms": stats["p95"]', script)
        self.assertIn('"peak_collision_pairs": peak_pairs', script)
        for name, flag in (("physics_circles_coincident_2d", "true"),
                           ("physics_circles_offset_2d", "false")):
            self.assertIn(f'"{name}"', py)
            self.assertIn(f'"{name}":', gd)
            self.assertIn(f"CoincidentCircles2DStress.new().run(self, scale, frames, {flag})", gd)
        gd_cases = re.search(r"const CASES := \[([\s\S]*?)\]", gd)
        py_cases = re.search(r"^CASES = \(([\s\S]*?)^\)", py, re.MULTILINE)
        self.assertIsNotNone(gd_cases)
        self.assertIsNotNone(py_cases)
        names_gd = re.findall(r'"([^"]+)"', gd_cases.group(1))
        names_py = re.findall(r'"([^"]+)"', py_cases.group(1))
        self.assertEqual(names_gd, names_py)
        self.assertEqual(len(names_gd), len(set(names_gd)))


if __name__ == "__main__":
    unittest.main()
