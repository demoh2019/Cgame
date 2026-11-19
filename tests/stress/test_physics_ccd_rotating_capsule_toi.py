"""Conservative nonlinear capsule-vs-static-sphere CCD contracts and reference tests."""
import math
import random
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def rotate(v, a):
    c, s = math.cos(a), math.sin(a)
    return (v[0] * c - v[1] * s, v[0] * s + v[1] * c)


def distance(center, axis, pivot, target, angle, half, fraction):
    orbit = rotate((center[0] - pivot[0], center[1] - pivot[1]), angle * fraction)
    mid = (pivot[0] + orbit[0], pivot[1] + orbit[1])
    direction = rotate(axis, angle * fraction)
    delta = (target[0] - mid[0], target[1] - mid[1])
    along = max(-half, min(half, delta[0] * direction[0] + delta[1] * direction[1]))
    return math.hypot(delta[0] - along * direction[0], delta[1] - along * direction[1])


def nonlinear_toi(center, axis, pivot, target, angle, half, radius):
    if not all(map(math.isfinite, (*center, *axis, *pivot, *target, angle, half, radius))):
        return "FALLBACK", None
    norm = math.hypot(*axis)
    if norm == 0 or angle == 0 or half < 0 or radius <= 0:
        return "FALLBACK", None
    axis = tuple(v / norm for v in axis)
    bound = abs(angle) * (math.dist(center, pivot) + half)
    if bound == 0:
        return "FALLBACK", None
    eps = max(1e-6, radius * 1e-5)
    fraction = 0.
    for _ in range(48):
        gap = distance(center, axis, pivot, target, angle, half, fraction) - radius
        if gap <= eps:
            return ("FALLBACK", None) if fraction == 0 else ("HIT", fraction)
        if fraction >= 1 or gap - eps > bound * (1 - fraction):
            return "MISS", None
        advance = gap * .95 / bound
        next_fraction = min(1., fraction + advance)
        if next_fraction <= fraction:
            return "FALLBACK", None
        fraction = next_fraction
    return "FALLBACK", None


class NonlinearCapsuleCCDTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.helper = (ROOT / "servers/physics_ccd_rotating_capsule_toi.h").read_text()
        cls.native = (ROOT / "tests/servers/test_godot_physics_ccd_rotating_capsule_toi.cpp").read_text()
        cls.pair = {}
        for dim in ("2d", "3d"):
            text = (ROOT / f"modules/godot_physics_{dim}/godot_body_pair_{dim}.cpp").read_text()
            name = "GodotBodyPair2D" if dim == "2d" else "GodotBodyPair3D"
            a, b = text.index(f"bool {name}::_test_ccd("), text.index(f"bool {name}::setup(")
            cls.pair[dim] = text[a:b]

    def test_pure_rotation_executes_before_legacy_linear_early_exit(self):
        for dim, src in self.pair.items():
            with self.subTest(dimension=dim):
                self.assertIn("motion_A.length_squared() == 0.0", src)
                self.assertIn("physics_ccd_rotating_capsule_toi(", src)
                self.assertLess(src.index("physics_ccd_rotating_capsule_toi("), src.index("relative_motion ="))
                self.assertIn("p_A->set_angular_velocity(p_A->get_angular_velocity() * fraction);", src)

    def test_only_opt_in_capsule_vs_static_sphere_with_uniform_scale(self):
        for dim, src in self.pair.items():
            with self.subTest(dimension=dim):
                self.assertIn("space->is_ccd_rotational_bounds_enabled()", src)
                self.assertIn("::BODY_MODE_STATIC", src)
                self.assertIn("::SHAPE_CAPSULE", src)
                self.assertIn("::SHAPE_" + ("CIRCLE" if dim == "2d" else "SPHERE"), src)
                self.assertIn("physics_ccd_uniform_sphere_scale(p_xform_A)", src)
                self.assertIn("physics_ccd_uniform_sphere_scale(p_xform_B)", src)

    def test_bounded_angular_advance_with_safe_miss_and_fallback(self):
        for required in ("for (int i = 0; i < 48; ++i)", "center_radius + p_half_segment",
                         "const double progress = gap * 0.95 / maximal_travel;",
                         "gap - epsilon > maximal_travel * remaining",
                         "PhysicsCCDRotatingCapsuleTOIResult::FALLBACK",
                         "p_center_of_mass + physics_ccd_rotate_vector"):
            self.assertIn(required, self.helper)

    def test_representative_grazing_and_full_step_tunneling(self):
        case = ((0, 0), (0, 1), (0, 0), (2.3, 0), math.pi / 2, 2.5, 0.5)
        status, fraction = nonlinear_toi(*case)
        self.assertEqual(status, "HIT")
        self.assertLess(fraction, 1.)
        tunneling = ((0, 0), (0, 1), (0, 0), (2.3, 0), math.pi, 2.5, 0.5)
        status, fraction = nonlinear_toi(*tunneling)
        self.assertEqual(status, "HIT")
        self.assertLess(fraction, .75)
        self.assertGreater(distance(*tunneling[:-1], 1), tunneling[-1])

    def test_center_of_mass_orbit_and_invalid_geometry(self):
        self.assertEqual(nonlinear_toi((2, 0), (0, 1), (0, 0),
                                       (0, 2), math.pi/2, .5, .3)[0], "HIT")
        self.assertEqual(nonlinear_toi((0, 0), (0, 1), (0, 0),
                                       (.2, 0), math.pi, 2.5, .5)[0], "FALLBACK")
        self.assertEqual(nonlinear_toi((0, 0), (0, 1), (0, 0),
                                       (100, 0), math.pi, 2.5, .5)[0], "MISS")

    def test_randomized_never_reports_miss_for_sampled_contact(self):
        rng = random.Random(191126)
        hits = 0
        misses = 0
        for case in range(3500):
            center = (rng.uniform(-3, 3), rng.uniform(-3, 3))
            pivot = (rng.uniform(-2, 2), rng.uniform(-2, 2))
            axis = rotate((0, 1), rng.uniform(-math.pi, math.pi))
            target = (rng.uniform(-5, 5), rng.uniform(-5, 5))
            angle = rng.uniform(-6.2, 6.2)
            half, radius = rng.uniform(.3, 3), rng.uniform(.1, .8)
            status, _ = nonlinear_toi(center, axis, pivot, target, angle, half, radius)
            misses += (status == "MISS")
            collided = any(distance(center, axis, pivot, target, angle, half, i/160) <= radius
                           for i in range(161))
            if collided:
                hits += 1
                self.assertNotEqual(status, "MISS", msg=f"False negative case {case}")
        self.assertGreater(hits, 50)
        self.assertGreater(misses, 100)

    def test_native_cases_2d_and_3d(self):
        self.assertEqual(self.native.count("TEST_CASE("), 7)
        self.assertIn("Fast rotational tunneling is detected", self.native)
        self.assertIn("Capsule sweeps around Z onto a stationary sphere", self.native)


if __name__ == "__main__":
    unittest.main()
