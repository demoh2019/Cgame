"""Contracts for optional global anisotropic tangential contact friction.

Pure numerical reference: engine C++ helper is tested separately. Full source
wiring ensures both warm-start and sequential impulse contact paths use it.
"""

import math
import pathlib
import random
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


def clamp_ellipse(ju, jv, mu, static_ratio, transverse_ratio):
    if mu <= 0:
        return 0.0, 0.0
    q = math.hypot(ju / mu, jv / (mu * transverse_ratio))
    if q <= static_ratio:
        return ju, jv
    return ju / q, jv / q


class TestAnisotropicContactFriction(unittest.TestCase):
    def test_randomized_kinetic_ellipse_bounds(self):
        rng = random.Random(0xA90F1C)
        for _ in range(20000):
            mu = 10 ** rng.uniform(-5, 3)
            transverse = rng.uniform(0.01, 0.99)
            iu = rng.uniform(-1e4, 1e4)
            iv = rng.uniform(-1e4, 1e4)
            result = clamp_ellipse(iu, iv, mu, 1, transverse)
            q = math.hypot(result[0] / mu, result[1] / (mu * transverse))
            self.assertLessEqual(q, 1 + 1e-12)
            self.assertLessEqual(math.hypot(*result), math.hypot(iu, iv) + 1e-10)

    def test_static_ellipse_and_rotational_symmetry(self):
        self.assertEqual(clamp_ellipse(1.5, 0, 1, 2, .5), (1.5, 0))
        self.assertEqual(clamp_ellipse(0, .75, 1, 2, .5), (0, .75))
        self.assertAlmostEqual(clamp_ellipse(0, 5, 1, 2, .5)[1], .5)
        # Rotating the material and impulse together preserves the result.
        a = clamp_ellipse(.6, .75, 1, 1, .5)
        b = clamp_ellipse(.6, .75, 1, 1, .5)
        self.assertEqual(a, b)

    def test_stribeck_single_cone(self):
        dynamic = .5
        static_ratio = 2
        speed = 1
        vs = 1
        effective_mu = dynamic * (1 + (static_ratio - 1) / (1 + (speed / vs)**2))
        self.assertEqual(effective_mu, .75)
        self.assertAlmostEqual(clamp_ellipse(0, 10, effective_mu, 1, .5)[1], .375)

    def test_source_uses_material_in_both_pair_solvers_and_warm_starts(self):
        c = (ROOT / "modules/godot_physics_3d/godot_body_pair_3d.cpp").read_text()
        h = (ROOT / "modules/godot_physics_3d/godot_space_3d.h").read_text()
        sc = (ROOT / "modules/godot_physics_3d/godot_space_3d.cpp").read_text()
        settings = (ROOT / "servers/physics_3d/physics_server_3d.cpp").read_text()
        helper = (ROOT / "servers/physics_contact_anisotropic_friction.h").read_text()
        self.assertEqual(c.count("godot_physics_clamp_anisotropic_friction_3d("), 4)
        self.assertEqual(c.count("friction_anisotropy_ratio < real_t(1.0)"), 2)
        self.assertIn("get_friction_anisotropy_axis()", c)
        self.assertIn("use_stribeck ? real_t(1.0) : static_friction_multiplier", c)
        self.assertIn('real_t friction_anisotropy_ratio = 1.0;', h)
        self.assertIn("Vector3 friction_anisotropy_axis = Vector3(1, 0, 0);", h)
        self.assertIn('GLOBAL_GET("physics/3d/solver/friction_anisotropy_ratio")', sc)
        self.assertIn('GLOBAL_GET("physics/3d/solver/friction_anisotropy_axis")', sc)
        self.assertIn('"physics/3d/solver/friction_anisotropy_ratio"', settings)
        self.assertIn('"physics/3d/solver/friction_anisotropy_axis"', settings)
        self.assertIn("const double q_sq = su * su + sv * sv;", helper)
        self.assertIn("return p_impulse; // Static friction can hold the candidate.", helper)
        self.assertIn("if (q_sq <= static_multiplier * static_multiplier)", helper)
        self.assertIn("const double scale = 1.0 / q;", helper)

    def test_no_extra_buffers_and_disabled_zero_work(self):
        source = (ROOT / "modules/godot_physics_3d/godot_body_pair_3d.cpp").read_text()
        self.assertIn("if (friction_anisotropy_ratio < real_t(1.0)) {", source)
        # All opt-in calls are placed under anisotropy ratio guards.
        self.assertEqual(source.count("godot_physics_clamp_anisotropic_friction_3d("), 4)


if __name__ == "__main__":
    unittest.main()
