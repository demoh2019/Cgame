"""Conservative mixed linear/angular capsule CCD source and numerical regressions."""

import math
import random
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def signed_gap(center, axis, pivot, target, motion, angle, half, radius, fraction):
    angle *= fraction
    c, s = math.cos(angle), math.sin(angle)
    cx, cy = center[0] - pivot[0], center[1] - pivot[1]
    origin = (
        pivot[0] + motion[0] * fraction + cx * c - cy * s,
        pivot[1] + motion[1] * fraction + cx * s + cy * c,
    )
    dx = axis[0] * c - axis[1] * s
    dy = axis[0] * s + axis[1] * c
    rx, ry = target[0] - origin[0], target[1] - origin[1]
    along = max(-half, min(half, rx * dx + ry * dy))
    return math.hypot(rx - along * dx, ry - along * dy) - radius


def conservative_toi(center, axis, pivot, target, motion, angle, half, radius):
    values = (*center, *axis, *pivot, *target, *motion, angle, half, radius)
    if not all(math.isfinite(value) for value in values):
        return "FALLBACK", None
    if math.hypot(*axis) == 0 or angle == 0 or half < 0 or radius <= 0:
        return "FALLBACK", None
    bound = math.hypot(*motion) + abs(angle) * (math.dist(center, pivot) + half)
    if not math.isfinite(bound) or bound <= 0:
        return "FALLBACK", None
    eps = max(1e-6, radius * 1e-5)
    fraction = 0.0
    for _ in range(64):
        gap = signed_gap(center, axis, pivot, target, motion, angle, half, radius, fraction)
        if gap <= eps:
            return ("FALLBACK", None) if fraction == 0 else ("HIT", fraction)
        if fraction >= 1 or gap - eps > bound * (1 - fraction):
            return "MISS", None
        advance = gap * .95 / bound
        nxt = min(1.0, fraction + advance)
        if nxt <= fraction:
            return "FALLBACK", None
        fraction = nxt
    return "FALLBACK", None


class MixedCapsuleTOITests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.helper = (ROOT / "servers/physics_ccd_nonlinear_capsule_toi.h").read_text()
        cls.native = (ROOT / "tests/servers/test_physics_ccd_nonlinear_capsule_toi.cpp").read_text()
        cls.pairs = {}
        for dim in ("2d", "3d"):
            source = (ROOT / "modules" / f"godot_physics_{dim}" /
                      f"godot_body_pair_{dim}.cpp").read_text()
            prefix = "GodotBodyPair2D" if dim == "2d" else "GodotBodyPair3D"
            a = source.index(f"bool {prefix}::_test_ccd(")
            b = source.index(f"bool {prefix}::setup(", a)
            cls.pairs[dim] = source[a:b]

    def test_advance_bound_accounts_for_linear_and_angular_motion(self):
        for token in (
            "linear_distance +", "angular_speed * double(p_step)",
            "(center_radius + p_half_segment)", "for (int i = 0; i < 64; ++i)",
            "p_linear_motion * real_t(fraction)",
            "physics_ccd_rotate_vector(center_from_pivot, p_omega, seconds)",
            "physics_ccd_rotate_vector(initial_axis, p_omega, seconds)",
            "const double progress = gap * 0.95 / maximal_travel;",
            "gap - epsilon > maximal_travel * remaining",
        ):
            self.assertIn(token, self.helper)

    def test_native_branches_precede_linear_only_early_exit(self):
        for dim, cast in self.pairs.items():
            with self.subTest(dim=dim):
                self.assertIn("physics_ccd_nonlinear_capsule_toi(", cast)
                self.assertLess(cast.index("physics_ccd_nonlinear_capsule_toi("),
                                cast.index("if (motion_A.length_squared() == 0.0)"))
                self.assertIn("space->is_ccd_rotational_bounds_enabled()", cast)
                self.assertIn("BODY_MODE_STATIC", cast)
                self.assertIn("SHAPE_CAPSULE", cast)
                self.assertIn("SHAPE_CIRCLE" if dim == "2d" else "SHAPE_SPHERE", cast)
                self.assertIn("physics_ccd_uniform_sphere_scale(p_xform_A)", cast)
                self.assertIn("physics_ccd_uniform_sphere_scale(p_xform_B)", cast)
                self.assertIn("p_A->set_linear_velocity(p_A->get_linear_velocity() * fraction)", cast)
                self.assertIn("p_A->set_angular_velocity(p_A->get_angular_velocity() * fraction)", cast)
                self.assertIn("p_A->get_transform().get_origin() + p_A->get_center_of_mass()" if dim == "2d" else
                              "p_A->get_transform().origin + p_A->get_center_of_mass()", cast)
        self.assertIn("!p_B->is_shape_set_as_one_way_collision(p_shape_B)", self.pairs["2d"])

    def test_moving_and_spinning_end_caps_tunnel_between_step_endpoints(self):
        for travel in (0.1, -0.1):
            args = ((0, 0), (0, 1), (0, 0), (2.3, 0), (travel, 0),
                    math.pi, 2.5, 0.5)
            state, fraction = conservative_toi(*args)
            self.assertEqual(state, "HIT")
            self.assertLess(fraction, 0.75)
            self.assertGreater(signed_gap(*args, 0), 0)
            self.assertGreater(signed_gap(*args, 1), 0)

    def test_world_translation_preserves_noncentral_pivot_toi(self):
        args = ((2, 0), (0, 1), (0, 0), (0, 2), (0.1, 0),
                math.pi / 2, .5, .3)
        state, fraction = conservative_toi(*args)
        off = (2048, -4096)
        relocated = tuple((v[0] + off[0], v[1] + off[1]) if i in (0, 2, 3) else v
                          for i, v in enumerate(args))
        state2, fraction2 = conservative_toi(*relocated)
        self.assertEqual(state, "HIT")
        self.assertEqual(state, state2)
        self.assertAlmostEqual(fraction, fraction2, places=9)

    def test_invalid_initial_overlap_and_guaranteed_misses(self):
        valid = ((0, 0), (0, 1), (0, 0), (2.3, 0), (.1, 0), math.pi, 2.5, .5)
        self.assertEqual(conservative_toi(*valid[:3], (100, 0), *valid[4:])[0], "MISS")
        self.assertEqual(conservative_toi(*valid[:3], (.2, 0), *valid[4:])[0], "FALLBACK")
        self.assertEqual(conservative_toi(*valid[:5], 0, *valid[6:])[0], "FALLBACK")

    def test_randomized_conservative_miss_never_excludes_sampled_impact(self):
        rng = random.Random(20261119)
        hits = 0
        misses = 0
        for trial in range(1200):
            center = (rng.uniform(-3, 3), rng.uniform(-3, 3))
            pivot = (rng.uniform(-2, 2), rng.uniform(-2, 2))
            theta = rng.uniform(-math.pi, math.pi)
            axis = (math.cos(theta), math.sin(theta))
            target = (rng.uniform(-4, 4), rng.uniform(-4, 4))
            motion = (rng.uniform(-1.5, 1.5), rng.uniform(-1.5, 1.5))
            angle = rng.uniform(-5.5, 5.5)
            half = rng.uniform(.2, 3)
            radius = rng.uniform(.1, .8)
            args = (center, axis, pivot, target, motion, angle, half, radius)
            result, fraction = conservative_toi(*args)
            hit = any(signed_gap(*args, i / 160) <= 0 for i in range(161))
            hits += hit
            misses += result == "MISS"
            if hit:
                self.assertNotEqual(result, "MISS", msg=f"False negative trial={trial}")
            if result == "HIT":
                self.assertIsNotNone(fraction)
                self.assertLessEqual(signed_gap(*args, fraction), max(1e-6, radius * 1e-5) + 1e-9)
        self.assertGreater(hits, 100)
        self.assertGreater(misses, 100)

    def test_native_cpp_and_engine_smoke_are_reachable_in_ci(self):
        self.assertIn("TEST_FORCE_LINK(test_physics_ccd_nonlinear_capsule_toi)", self.native)
        self.assertIn("[MixedCapsuleTOI]", self.native)
        script_name = "physics_ccd_nonlinear_capsule_toi_regression.gd"
        smoke = (ROOT / "tests/stress" / script_name).read_text()
        self.assertIn("2D/3D mixed nonlinear capsule CCD regression passed.", smoke)
        self.assertIn("Vector2(2048.0, -4096.0)", smoke)
        ci = (ROOT / ".github/workflows/whole-engine-stress.yml").read_text()
        self.assertIn('--test-case="*MixedCapsuleTOI*"', ci)
        self.assertIn(script_name, ci)
        self.assertIn("physics-mixed-capsule-toi.log", ci)
        self.assertIn("physics-mixed-capsule-ccd.log", ci)


if __name__ == "__main__":
    unittest.main()
