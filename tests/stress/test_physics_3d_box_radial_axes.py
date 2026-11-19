"""Translation-invariant radial SAT axes for 3D box/capsule and box/cylinder.

The radial direction from a box vertex to a capsule/cylinder axis is
perpendicular to that axis through the *other shape's origin*, not the
world origin. This file checks C++ source contracts and 5,000 randomized
geometry reference cases. A headless Godot test covers actual contacts.
"""
from pathlib import Path
import math
import random
import re
import unittest


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "modules/godot_physics_3d/godot_collision_solver_3d_sat.cpp"
RUNTIME = ROOT / "tests/stress/physics_box_radial_axis_translation_regression.gd"
WORKLOAD = ROOT / "tests/stress/physics_box_radial_axis_3d.gd"
STRESS = ROOT / "tests/stress/stress.gd"
RUNNER = ROOT / "tests/stress/run.py"


def dot(a, b):
    return sum(a[i] * b[i] for i in range(3))


def norm(a):
    return math.sqrt(dot(a, a))


def radial_axis(point, line_origin, direction):
    v = tuple(point[i] - line_origin[i] for i in range(3))
    k = dot(v, direction)
    return tuple(v[i] - direction[i] * k for i in range(3))


class BoxRadialAxisSAT(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source = SOURCE.read_text(encoding="utf-8")
        cap = source.index("static void _collision_box_capsule(")
        cyl = source.index("static void _collision_box_cylinder(", cap)
        poly = source.index("static void _collision_box_convex_polygon(", cyl)
        cls.capsule = source[cap:cyl]
        cls.cylinder = source[cyl:poly]

    def test_capsule_radial_axes_are_relative_to_capsule_center(self):
        code = self.capsule
        self.assertIn("const Vector3 from_capsule = point - p_transform_b.origin;", code)
        self.assertIn("Vector3 radial = from_capsule - cyl_axis * from_capsule.dot(cyl_axis);", code)
        self.assertIn("Math::is_zero_approx(radial.length_squared())", code)
        self.assertIn("separator.test_axis(radial.normalized())", code)
        self.assertNotIn("Plane(cyl_axis).project(point)", code)
        self.assertIn("separator.test_previous_axis()", code)
        self.assertIn("separator.generate_contacts();", code)
        self.assertIn("capsule_B->get_height()", code)

    def test_cylinder_radial_axes_are_relative_to_cylinder_center(self):
        code = self.cylinder
        self.assertIn("const Vector3 from_cylinder = point - p_transform_b.origin;", code)
        self.assertIn("Vector3 radial = from_cylinder - cyl_axis * from_cylinder.dot(cyl_axis);", code)
        self.assertIn("Math::is_zero_approx(radial.length_squared())", code)
        self.assertIn("separator.test_axis(radial.normalized())", code)
        self.assertNotIn("Plane(cyl_axis).project(point)", code)
        self.assertIn("cylinder_B->get_height()", code)
        self.assertIn("separator.test_previous_axis()", code)
        self.assertIn("separator.generate_contacts();", code)
        # The end-cap rim algorithm is independent and must still execute.
        self.assertIn("Vector3 cap_pos = p_transform_b.origin", code)
        self.assertIn("tangent.cross(edge_dir)", code)

    def test_radial_axis_is_independent_of_shared_world_translation(self):
        rng = random.Random(20261120)
        for _ in range(5000):
            axis = tuple(rng.uniform(-1.0, 1.0) for _ in range(3))
            length = norm(axis)
            if length < 0.001:
                continue
            axis = tuple(a / length for a in axis)
            center = tuple(rng.uniform(-100.0, 100.0) for _ in range(3))
            vertex = tuple(center[i] + rng.uniform(-15.0, 15.0) for i in range(3))
            translation = tuple(rng.uniform(-100_000.0, 100_000.0) for _ in range(3))
            original = radial_axis(vertex, center, axis)
            translated = radial_axis(
                tuple(vertex[i] + translation[i] for i in range(3)),
                tuple(center[i] + translation[i] for i in range(3)),
                axis,
            )
            for x, y in zip(original, translated):
                self.assertAlmostEqual(x, y, delta=1e-8)
            self.assertAlmostEqual(dot(original, axis), 0.0, delta=1e-10)

    def test_world_origin_projection_would_change_with_translation(self):
        axis = (0.0, 1.0, 0.0)
        center, vertex = (1.0, 0.0, 0.0), (1.3, 2.0, 0.3)
        translation = (1000.0, -4000.0, 8000.0)
        correct = radial_axis(vertex, center, axis)
        far = radial_axis(tuple(vertex[i] + translation[i] for i in range(3)),
                          tuple(center[i] + translation[i] for i in range(3)), axis)
        bad = radial_axis(tuple(vertex[i] + translation[i] for i in range(3)),
                          (0.0, 0.0, 0.0), axis)
        self.assertAlmostEqual(norm(tuple(correct[i] - far[i] for i in range(3))), 0.0, delta=1e-11)
        self.assertGreater(norm(tuple(correct[i] - bad[i] for i in range(3))), 100.0)

    def test_headless_coverage_includes_far_translations_and_both_shapes(self):
        code = RUNTIME.read_text(encoding="utf-8")
        self.assertIn("PhysicsServer3D.capsule_shape_create()", code)
        self.assertIn("PhysicsServer3D.cylinder_shape_create()", code)
        self.assertIn("for shape_rid in [capsule, cylinder]:", code)
        self.assertIn("Vector3(4096.0, -8192.0, 12288.0)", code)
        self.assertIn("Vector3(-16384.0, 8192.0, -4096.0)", code)
        self.assertIn("for rotated in [false, true]:", code)
        self.assertIn("state.intersect_shape(query, 8)", code)
        self.assertIn("state.collide_shape(query, 8)", code)
        self.assertIn("base_contact[case_index].normalized().dot(contact.normalized())", code)
        self.assertIn("PhysicsServer3D.free_rid(space)", code)

    def test_four_new_stress_cases_are_registered_in_both_runners(self):
        gd = STRESS.read_text(encoding="utf-8")
        py = RUNNER.read_text(encoding="utf-8")
        workload = WORKLOAD.read_text(encoding="utf-8")
        self.assertIn("func run(tree: SceneTree, scale: int, frames: int, capsule: bool, far_origin: bool)", workload)
        self.assertIn('"frame_p95_ms": stats["p95"]', workload)
        self.assertIn('"peak_collision_pairs": peak_pairs', workload)
        for suffix, shape, far in (
            ("capsule_near", "true", "false"),
            ("capsule_far", "true", "true"),
            ("cylinder_near", "false", "false"),
            ("cylinder_far", "false", "true"),
        ):
            name = f"physics_box_{suffix}_3d"
            self.assertIn(f'"{name}"', py)
            self.assertIn(f'"{name}":', gd)
            self.assertIn(
                f"BoxRadial3DStress.new().run(self, scale, frames, {shape}, {far})",
                gd,
            )
        gd_cases = re.search(r"const CASES := \[([\s\S]*?)\]", gd)
        py_cases = re.search(r"^CASES = \(([\s\S]*?)^\)", py, re.MULTILINE)
        self.assertIsNotNone(gd_cases)
        self.assertIsNotNone(py_cases)
        actual_gd = re.findall(r'"([^"]+)"', gd_cases.group(1))
        actual_py = re.findall(r'"([^"]+)"', py_cases.group(1))
        self.assertEqual(actual_gd, actual_py)
        self.assertEqual(len(actual_gd), len(set(actual_gd)))


if __name__ == "__main__":
    unittest.main()
