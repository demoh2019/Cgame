"""Randomized reference and source-wiring contracts for Stribeck-like contact friction."""

import math
import pathlib
import random
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


def model(dynamic, multiplier, speed, transition):
    if not math.isfinite(dynamic) or dynamic <= 0:
        return 0.0
    if not math.isfinite(multiplier) or multiplier <= 1 or not math.isfinite(speed) or speed < 0 or not math.isfinite(transition) or transition <= 0:
        return dynamic
    ratio = speed / transition
    if ratio >= 1e6:
        return dynamic
    return dynamic * (1 + (multiplier - 1) / (1 + ratio * ratio))


class TestStribeckFriction(unittest.TestCase):
    def test_material_contract_randomized(self):
        rng = random.Random(932624)
        for _ in range(30000):
            mu = 10 ** rng.uniform(-4, 1)
            multiplier = 1 + rng.uniform(0, 5)
            transition = 10 ** rng.uniform(-4, 2)
            low = rng.uniform(0, 10)
            high = low + rng.uniform(0, 300)
            slow, fast = (model(mu, multiplier, speed, transition) for speed in (low, high))
            self.assertTrue(all(math.isfinite(x) for x in (slow, fast)))
            self.assertLessEqual(fast, slow + 1e-12)
            self.assertGreaterEqual(fast, mu)
            self.assertLessEqual(slow, mu * multiplier + 1e-12)
            self.assertEqual(model(mu, multiplier, low, 0), mu)
            self.assertEqual(model(mu, 1, low, transition), mu)

    def test_cone_magnitude_and_continuity(self):
        self.assertAlmostEqual(model(.5, 2, 0, 1), 1.0)
        self.assertAlmostEqual(model(.5, 2, 1, 1), .75)
        self.assertAlmostEqual(model(.5, 2, 3, 1), .55)
        h = 1e-5
        self.assertLess(abs(model(.5, 2, 1+h, 1) - model(.5, 2, 1-h, 1)), 1e-4)
        self.assertAlmostEqual(model(.5, 2, 1e9, 1), .5)

    def test_invalid_fallback(self):
        self.assertEqual(model(float("nan"), 2, 1, 1), 0.0)
        self.assertEqual(model(.5, 2, float("inf"), 1), .5)
        self.assertEqual(model(.5, 2, 1, float("nan")), .5)

    def test_integrated_rigid_and_soft_pairs_opt_in(self):
        src = (ROOT / "modules/godot_physics_3d/godot_body_pair_3d.cpp").read_text()
        space_h = (ROOT / "modules/godot_physics_3d/godot_space_3d.h").read_text()
        space_cpp = (ROOT / "modules/godot_physics_3d/godot_space_3d.cpp").read_text()
        physics_server = (ROOT / "servers/physics_3d/physics_server_3d.cpp").read_text()
        header = (ROOT / "servers/physics_contact_velocity_friction.h").read_text()
        self.assertIn("stribeck_transition_velocity = 0.0;", space_h)
        self.assertIn('GLOBAL_GET("physics/3d/solver/stribeck_transition_velocity")', space_cpp)
        self.assertIn('"physics/3d/solver/stribeck_transition_velocity"', physics_server)
        self.assertIn("godot_physics_stribeck_friction_coefficient(", header)
        self.assertEqual(src.count("godot_physics_stribeck_friction_coefficient("), 2)
        self.assertEqual(src.count("const bool use_stribeck = stribeck_velocity >"), 2)
        self.assertEqual(src.count("if (use_stribeck) {"), 2)
        self.assertIn("godot_physics_clamp_static_friction_3d(c.acc_tangent_impulse, jtMax, real_t(1.0))", src)
        self.assertIn("space->get_stribeck_transition_velocity()", src)
        self.assertIn("const real_t cached_tangent_limit = mixed_friction * space->get_static_friction_multiplier()", src)


if __name__ == "__main__":
    unittest.main()
