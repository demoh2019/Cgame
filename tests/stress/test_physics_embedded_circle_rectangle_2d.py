"""Contracts for Box2D-style 2D circle/rectangle interior face contacts.

The fast path is only valid for unswept circle/rectangle pairs under
unit-orthogonal transforms. The legacy SAT still handles scaling,
shearing, cast motion and degenerate rectangles.
"""
from pathlib import Path
import math
import random
import re
import unittest


ROOT = Path(__file__).resolve().parents[2]
SAT = ROOT / "modules/godot_physics_2d/godot_collision_solver_2d_sat.cpp"
RUNTIME = ROOT / "tests/stress/physics_embedded_circle_rectangle_2d_regression.gd"
BENCH = ROOT / "tests/stress/physics_embedded_circle_rectangle_2d.gd"
STRESS = ROOT / "tests/stress/stress.gd"
RUNNER = ROOT / "tests/stress/run.py"


def rotate(v, angle):
    c, s = math.cos(angle), math.sin(angle)
    return (c * v[0] - s * v[1], s * v[0] + c * v[1])


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1]


def embedded_manifold(local_center, extents, radius, margin_a, margin_b, angle):
    dx = extents[0] - abs(local_center[0])
    dy = extents[1] - abs(local_center[1])
    nearest_x = dx <= dy
    if nearest_x:
        local_exit = (-1.0 if local_center[0] < 0 else 1.0, 0.0)
    else:
        local_exit = (0.0, -1.0 if local_center[1] < 0 else 1.0)
    outward = rotate(local_exit, angle)
    normal = (-outward[0], -outward[1])
    center = rotate(local_center, angle)
    expanded_radius = radius + margin_a
    clearance = dx if nearest_x else dy
    point_a = tuple(center[i] + normal[i] * expanded_radius for i in range(2))
    point_b = tuple(center[i] + outward[i] * (clearance + margin_b) for i in range(2))
    return normal, outward, point_a, point_b, clearance


class EmbeddedCircleRectangle2D(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source = SAT.read_text(encoding="utf-8")
        begin = source.index("static void _collision_circle_rectangle(")
        end = source.index("static void _collision_circle_capsule(", begin)
        cls.code = source[begin:end]

    def test_embedded_analytic_guard_is_conservative(self):
        code = self.code
        self.assertIn("!p_cast_A && !p_cast_B", code)
        self.assertIn("p_margin_A >= 0.0 && p_margin_B >= 0.0", code)
        self.assertIn("_is_unit_orthogonal_transform(p_transform_a)", code)
        self.assertIn("_is_unit_orthogonal_transform(p_transform_b)", code)
        self.assertIn("half_extents.x > real_t(0.0) && half_extents.y > real_t(0.0)", code)
        self.assertIn("Math::abs(local_center.x) <= half_extents.x", code)
        self.assertIn("Math::abs(local_center.y) <= half_extents.y", code)

    def test_contact_uses_exit_face_and_preserves_legacy_sat(self):
        code = self.code
        self.assertIn("Box2D-style embedded circle/rectangle manifold", code)
        self.assertIn("const bool nearest_x_face = clearance_x <= clearance_y;", code)
        self.assertIn("p_transform_b.basis_xform(local_exit_normal)", code)
        self.assertIn("const Vector2 normal = -exit_normal;", code)
        self.assertIn("circle_A->get_radius() + p_margin_A", code)
        self.assertIn("nearest_face_distance + p_margin_B", code)
        self.assertIn("p_collector->collided = true;", code)
        self.assertIn("p_collector->normal = normal;", code)
        self.assertIn("center + normal * circle_radius", code)
        self.assertIn("center + exit_normal * (nearest_face_distance + p_margin_B)", code)
        self.assertIn("*p_collector->sep_axis = Vector2();", code)
        self.assertIn("SeparatorAxisTest2D<GodotCircleShape2D, GodotRectangleShape2D>", code)
        self.assertIn("separator.generate_contacts();", code)
        self.assertLess(code.index("Box2D-style embedded circle/rectangle manifold"),
                        code.index("SeparatorAxisTest2D<GodotCircleShape2D, GodotRectangleShape2D>"))

    def test_5000_rotated_embedded_contacts_push_to_nearest_exit(self):
        rng = random.Random(20261120)
        # Offset, radii, margins and rotation all vary across the same
        # analytic manifold; no allocations or expensive SAT are required.
        for _ in range(5000):
            extent_x = rng.uniform(0.05, 6.0)
            extent_y = rng.uniform(0.05, 6.0)
            extents = (extent_x, extent_y)
            local_center = (rng.uniform(-extent_x, extent_x),
                            rng.uniform(-extent_y, extent_y))
            radius = rng.uniform(0.0, 2.0)
            margin_a = rng.uniform(0.0, 0.2)
            margin_b = rng.uniform(0.0, 0.2)
            angle = rng.uniform(-math.pi, math.pi)
            normal, outward, point_a, point_b, clearance = embedded_manifold(
                local_center, extents, radius, margin_a, margin_b, angle
            )
            separation = tuple(point_b[i] - point_a[i] for i in range(2))
            expected = radius + margin_a + clearance + margin_b
            self.assertGreaterEqual(clearance, 0.0)
            self.assertAlmostEqual(dot(normal, outward), -1.0, places=12)
            self.assertAlmostEqual(dot(separation, outward), expected, places=11)
            self.assertAlmostEqual(dot(separation, normal), -expected, places=11)
            self.assertTrue(math.isfinite(point_a[0]) and math.isfinite(point_b[1]))
            # The solver applies impulse -normal to A, which must point
            # towards the selected escape face.
            self.assertAlmostEqual(dot(tuple(-n for n in normal), outward), 1.0, places=12)

    def test_headless_regression_checks_inside_outside_and_scaled_fallback(self):
        source = RUNTIME.read_text(encoding="utf-8")
        self.assertIn("for mode in range(3):", source)
        self.assertIn("basis.scaled_local(Vector2(1.5, 1.0))", source)
        self.assertIn("PhysicsServer2D.space_get_direct_state(space)", source)
        self.assertIn("state.intersect_shape(query, 8)", source)
        self.assertIn("state.collide_shape(query, 8)", source)
        self.assertIn("point.is_finite()", source)
        self.assertIn("exit_pose.origin.x < 0.77", source)
        self.assertIn("PhysicsServer2D.free_rid(dynamic_circle)", source)
        self.assertIn("PhysicsServer2D.free_rid(space)", source)

    def test_stress_cases_match_runner_and_are_unique(self):
        benchmark = BENCH.read_text(encoding="utf-8")
        stress = STRESS.read_text(encoding="utf-8")
        runner = RUNNER.read_text(encoding="utf-8")
        self.assertIn("func run(tree: SceneTree, scale: int, frames: int, embedded: bool)", benchmark)
        self.assertIn("mini(256 * scale, 4096)", benchmark)
        self.assertIn('"peak_collision_pairs": peak_pairs', benchmark)
        self.assertIn('"frame_p95_ms": stats["p95"]', benchmark)
        for name, enabled in (("physics_circle_rectangle_embedded_2d", "true"),
                              ("physics_circle_rectangle_exterior_2d", "false")):
            self.assertIn(f'"{name}"', runner)
            self.assertIn(f'"{name}":', stress)
            self.assertIn(f"EmbeddedCircleRectangle2DStress.new().run(self, scale, frames, {enabled})", stress)
        gd_cases = re.search(r"const CASES := \[([\s\S]*?)\]", stress)
        py_cases = re.search(r"^CASES = \(([\s\S]*?)^\)", runner, re.MULTILINE)
        self.assertIsNotNone(gd_cases)
        self.assertIsNotNone(py_cases)
        names_gd = re.findall(r'"([^"]+)"', gd_cases.group(1))
        names_py = re.findall(r'"([^"]+)"', py_cases.group(1))
        self.assertEqual(names_gd, names_py)
        self.assertEqual(len(names_gd), len(set(names_gd)))


if __name__ == "__main__":
    unittest.main()
