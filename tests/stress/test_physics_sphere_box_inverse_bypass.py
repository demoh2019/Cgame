"""Sphere/box closest-point fast path: source and numerical contracts.

The identity transform is a pure translation, so a matrix inversion and its
subsequent world transform can be bypassed without changing contact geometry.
Headless Godot tests validate the real query and manifold paths.
"""
from pathlib import Path
import math
import random
import re
import unittest


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "modules/godot_physics_3d/godot_collision_solver_3d_sat.cpp"
RUNTIME = ROOT / "tests/stress/physics_sphere_box_fast_path_regression.gd"
BENCH = ROOT / "tests/stress/physics_sphere_box_3d.gd"
GDSCRIPT = ROOT / "tests/stress/stress.gd"
RUNNER = ROOT / "tests/stress/run.py"


def closest_local(center, extents):
    return tuple(max(-e, min(e, x)) for x, e in zip(center, extents))


def add(a, b):
    return tuple(x + y for x, y in zip(a, b))


def sub(a, b):
    return tuple(x - y for x, y in zip(a, b))


class SphereBoxBypassTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source = SOURCE.read_text(encoding="utf-8")
        begin = source.index("static void _collision_sphere_box(")
        end = source.index("static void _collision_sphere_capsule(", begin)
        cls.sphere_box = source[begin:end]

    def test_fast_path_skips_affine_inverse_only_for_identity_box_basis(self):
        code = self.sphere_box
        self.assertIn("const bool unrotated_box = p_transform_b.basis == Basis();", code)
        self.assertIn("const Transform3D box_inverse = unrotated_box ?", code)
        self.assertIn("Transform3D(Basis(), -p_transform_b.origin) : p_transform_b.affine_inverse();", code)
        self.assertIn("p_transform_a.origin - p_transform_b.origin : box_inverse.xform(p_transform_a.origin)", code)
        self.assertIn("unrotated_box ? p_transform_b.origin + nearest : p_transform_b.xform(nearest)", code)
        self.assertIn("const Basis face_normal_basis = box_inverse.basis.transposed();", code)

    def test_scaled_rotated_and_margin_geometry_kept(self):
        code = self.sphere_box
        self.assertIn("box_inverse.xform(p_transform_a.origin)", code)
        self.assertIn("p_transform_b.xform(nearest)", code)
        self.assertIn("sphere_A->get_radius() * p_transform_a.basis[0].length()", code)
        self.assertIn("const real_t combined_radius = radius + p_margin_a + p_margin_b;", code)
        self.assertIn("const bool center_inside =", code)
        self.assertIn("if (center_inside) {", code)
        self.assertIn("nearest = p_transform_a.origin + exit_normal * nearest_face_distance;", code)
        self.assertIn("const real_t distance_squared = delta.length_squared();", code)
        self.assertIn("p_collector->collided = true;", code)
        self.assertIn("p_collector->call(point_a, point_b, axis);", code)

    def test_identity_transform_closest_point_equivalent_to_affine_inverse(self):
        rng = random.Random(20261120)
        for _ in range(10000):
            origin = tuple(rng.uniform(-20000.0, 20000.0) for _ in range(3))
            local = tuple(rng.uniform(-8.0, 8.0) for _ in range(3))
            extents = tuple(rng.uniform(0.05, 5.0) for _ in range(3))
            world = add(origin, local)

            # Full old identity-inverse composition: identity basis with
            # translation -origin, followed by transform back to world.
            inverse_transform_center = add(world, tuple(-x for x in origin))
            fast_center = sub(world, origin)
            old_world_nearest = add(origin, closest_local(inverse_transform_center, extents))
            new_world_nearest = add(origin, closest_local(fast_center, extents))
            self.assertEqual(fast_center, inverse_transform_center)
            self.assertEqual(new_world_nearest, old_world_nearest)

            radius = rng.uniform(0.0, 2.0)
            margin_a, margin_b = rng.uniform(0.0, 0.2), rng.uniform(0.0, 0.2)
            delta = sub(new_world_nearest, world)
            squared = sum(x * x for x in delta)
            intersects_fast = squared <= (radius + margin_a + margin_b) ** 2
            intersects_old = sum((x - y) ** 2 for x, y in zip(old_world_nearest, world)) <= (
                radius + margin_a + margin_b
            ) ** 2
            self.assertEqual(intersects_fast, intersects_old)
            self.assertTrue(math.isfinite(squared))

    def test_runtime_has_inside_outside_rotated_and_scaled_cases(self):
        source = RUNTIME.read_text(encoding="utf-8")
        self.assertIn("PhysicsServer3D.box_shape_create()", source)
        self.assertIn("PhysicsServer3D.sphere_shape_create()", source)
        self.assertIn("Basis().scaled(Vector3(1.5, 1.0, 1.0))", source)
        self.assertIn("Basis(Vector3.UP, 0.37)", source)
        self.assertIn("for case_index in range(bases.size()):", source)
        self.assertIn("state.intersect_shape(query, 8)", source)
        self.assertIn("state.collide_shape(query, 8)", source)
        self.assertIn("point.is_finite()", source)
        self.assertIn("Vector3.ZERO, \"hit\": true", source)
        self.assertIn("PhysicsServer3D.free_rid(space)", source)

    def test_both_stress_cases_present_with_same_pair_count(self):
        gdscript = GDSCRIPT.read_text(encoding="utf-8")
        runner = RUNNER.read_text(encoding="utf-8")
        bench = BENCH.read_text(encoding="utf-8")
        self.assertIn("func run(tree: SceneTree, scale: int, frames: int, rotated: bool)", bench)
        self.assertIn("var count := mini(256 * scale, 4096)", bench)
        self.assertIn('"peak_collision_pairs": peak_pairs', bench)
        self.assertIn('"frame_p95_ms": stats["p95"]', bench)
        for name, flag in (("physics_sphere_box_identity_3d", "false"),
                           ("physics_sphere_box_rotated_3d", "true")):
            self.assertIn(f'"{name}"', runner)
            self.assertIn(f'"{name}":', gdscript)
            self.assertIn(f"SphereBox3DStress.new().run(self, scale, frames, {flag})", gdscript)

        gd_cases = re.search(r"const CASES := \[([\s\S]*?)\]", gdscript)
        py_cases = re.search(r"^CASES = \(([\s\S]*?)^\)", runner, re.MULTILINE)
        self.assertIsNotNone(gd_cases)
        self.assertIsNotNone(py_cases)
        cases_gd = re.findall(r'"([^"]+)"', gd_cases.group(1))
        cases_py = re.findall(r'"([^"]+)"', py_cases.group(1))
        self.assertEqual(cases_gd, cases_py)
        self.assertEqual(len(set(cases_gd)), len(cases_gd))


if __name__ == "__main__":
    unittest.main()
