"""Conservative swept-center-sphere CCD pruning: source and geometry checks.

This opt-in culling happens *before* legacy support-ray CCD for spinning
pairs, never creates contact or a TOI, and leaves all unbounded/invalid
shapes on the original narrowphase path. Only geometry and static code
contracts are checked here; a built Cgame is needed for runtime behavior.
"""

import math
import random
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "servers/physics_ccd_rotational_sphere_cull.h"
CPPTEST = ROOT / "tests/servers/test_godot_physics_ccd_rotational_sphere_cull.cpp"


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def may_overlap(box_a, pivot_a, box_b, pivot_b, motion):
    """Independent Python model; boxes are tuples (center, half_extent)."""
    ra = math.hypot(*(abs(c - p) + abs(h) for c, p, h in
                      zip(box_a[0], pivot_a, box_a[1])))
    rb = math.hypot(*(abs(c - p) + abs(h) for c, p, h in
                      zip(box_b[0], pivot_b, box_b[1])))
    rel = tuple(a - b for a, b in zip(pivot_a, pivot_b))
    motion_sq = dot(motion, motion)
    fraction = max(0.0, min(1.0, -dot(rel, motion) / motion_sq)) if motion_sq else 0.0
    closest = tuple(x + fraction * v for x, v in zip(rel, motion))
    slack = (ra + rb + math.hypot(*rel) + math.hypot(*motion)) * 1e-6 + 1e-6
    return dot(closest, closest) <= (ra + rb + slack) ** 2


def rotating_point(local_point, linear_motion, pivot, angle, fraction):
    c, s = math.cos(angle * fraction), math.sin(angle * fraction)
    x, y = local_point
    return (pivot[0] + linear_motion[0] * fraction + x*c - y*s,
            pivot[1] + linear_motion[1] * fraction + x*s + y*c)


class CCDRotationalSphereCullContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.helper = HELPER.read_text(encoding="utf-8")
        cls.native = CPPTEST.read_text(encoding="utf-8")
        cls.sections = {}
        for dim in ("2d", "3d"):
            s = (ROOT / "modules" / f"godot_physics_{dim}" /
                 f"godot_body_pair_{dim}.cpp").read_text(encoding="utf-8")
            fn = f"bool GodotBodyPair{dim.upper()}::_test_ccd("
            a = s.index(fn)
            b = s.index(f"bool GodotBodyPair{dim.upper()}::setup(", a)
            cls.sections[dim] = s[a:b]
            cls.sections[dim + "_full"] = s

    def test_opt_in_existing_rotational_broadphase_flag(self):
        for dim in ("2d", "3d"):
            with self.subTest(dim=dim):
                source = self.sections[dim]
                self.assertIn("space->is_ccd_rotational_bounds_enabled()", source)
                self.assertIn("physics_ccd_rotational_sphere_bounds_may_overlap(", source)
                self.assertIn('#include "servers/physics_ccd_rotational_sphere_cull.h"',
                              self.sections[dim + "_full"])
                self.assertIn("return false;", source)

    def test_excludes_unbounded_and_ray_shapes(self):
        for dim in ("2d", "3d"):
            source = self.sections[dim]
            marker = "physics_ccd_rotational_sphere_bounds_may_overlap("
            guard = source[source.index("if (space->is_ccd_rotational_bounds_enabled()"):source.index(marker)]
            enum = "PS2DE" if dim == "2d" else "PS3DE"
            self.assertIn(f"{enum}::SHAPE_WORLD_BOUNDARY", guard)
            self.assertIn(f"{enum}::SHAPE_SEPARATION_RAY", guard)
            self.assertIn("p_A->get_angular_velocity()", guard)
            self.assertIn("p_B->get_angular_velocity()", guard)

    def test_relative_motion_and_center_of_mass_pivots(self):
        for dim in ("2d", "3d"):
            source = self.sections[dim]
            self.assertIn("p_xform_A.xform(shape_A_ptr->get_aabb())", source)
            self.assertIn("p_xform_B.xform(shape_B_ptr->get_aabb())", source)
            self.assertIn("p_A->get_center_of_mass()", source)
            self.assertIn("p_B->get_center_of_mass()", source)
            self.assertIn("relative_motion", source)

    def test_invalid_data_fails_open(self):
        self.assertIn("if (!p_world_bounds_a.is_finite()", self.helper)
        self.assertIn("!p_world_pivot_a.is_finite()", self.helper)
        self.assertIn("!p_relative_linear_motion.is_finite()", self.helper)
        self.assertIn("if (!support_a.is_finite() || !support_b.is_finite())", self.helper)
        self.assertIn("if (!Math::is_finite(closest_sq)", self.helper)
        self.assertIn("return true;", self.helper)

    def test_swept_closest_approach_in_double(self):
        self.assertIn("const double motion_sq =", self.helper)
        self.assertIn("const double projection =", self.helper)
        self.assertIn("CLAMP(-projection / motion_sq, 0.0, 1.0)", self.helper)
        self.assertIn("const double conservative_radius = radius_sum + slack;", self.helper)
        self.assertIn("return closest_sq <= conservative_radius * conservative_radius;", self.helper)

    def test_fixed_2d_and_3d_geometry_examples(self):
        for n in (2, 3):
            zero = (0.0,) * n
            far = (0.0, 100.0) + ((0.0,) if n == 3 else ())
            move = (0.0, 30.0) + ((0.0,) if n == 3 else ())
            large = (10.0, 1.0) + ((1.0,) if n == 3 else ())
            small = (1.0,) * n
            self.assertFalse(may_overlap((zero, large), zero, (far, small), far, move))
            near = (0.0, 11.0) + ((0.0,) if n == 3 else ())
            self.assertTrue(may_overlap((zero, large), zero, (near, small), near, zero))

    def test_numerical_rotating_support_points_never_culled_if_touching(self):
        rng = random.Random(20261119)
        candidates = 0
        true_hits = 0
        for i in range(10000):
            # A rotating, off-center rectangle about its rigid-body COM.
            center = (rng.uniform(-8, 8), rng.uniform(-8, 8))
            half = (rng.uniform(.05, 2), rng.uniform(.05, 2))
            initial_corners = [(center[0] + sx*half[0], center[1] + sy*half[1])
                               for sx in (-1, 1) for sy in (-1, 1)]
            angle = rng.uniform(-math.pi, math.pi)
            linear_motion = (rng.uniform(-10, 10), rng.uniform(-10, 10))
            target_center = (rng.uniform(-15, 15), rng.uniform(-15, 15))
            target_radius = rng.uniform(.1, 2)
            a_box = (center, half)
            b_box = (target_center, (target_radius, target_radius))
            motion = linear_motion
            candidate = may_overlap(a_box, (0.0, 0.0), b_box, target_center, motion)
            candidates += candidate
            # A hit is any sampled corner reaching the target sphere. The
            # exact path lies inside the swept COM sphere at every fraction.
            found = any(
                math.dist(rotating_point(corner, linear_motion, (0, 0), angle, t/24),
                          target_center) <= target_radius
                for corner in initial_corners for t in range(25)
            )
            if found:
                true_hits += 1
                self.assertTrue(candidate, msg=f"False-negative at random case {i}")
        self.assertGreater(true_hits, 10)
        self.assertLess(candidates, 10000)

    def test_native_cpp_tests_cover_both_dimensions(self):
        self.assertEqual(self.native.count("TEST_CASE("), 6)
        self.assertIn("[GodotPhysics2D] Rotating long box", self.native)
        self.assertIn("[GodotPhysics3D] Rotating long box", self.native)
        self.assertIn("Invalid geometry falls back to narrowphase", self.native)


if __name__ == "__main__":
    unittest.main()
