"""Deterministic numerical and source contracts for FEM tetrahedral damage."""

import math
import pathlib
import random
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


def evolve(damage, density, yield_density, rate, dt):
    if any(not math.isfinite(x) for x in (damage, density, yield_density, rate, dt)):
        return None
    if not 0 <= damage <= .95 or density < 0 or yield_density <= 0 or rate <= 0 or dt <= 0:
        return None
    if density <= yield_density or damage == .95:
        return None
    severity = min(32., density/yield_density-1)
    survival = math.exp(-rate*dt*severity) if rate*dt*severity < 700 else 0.
    return min(.95, damage+(1-damage)*(1-survival))


def alpha(base, damage):
    return base/min(1., max(.05, 1-damage))


class TestProgressiveTetraDamage(unittest.TestCase):
    def test_30000_randomized_monotone_loading(self):
        rng = random.Random(0xF3DA6E)
        increased = 0
        for _ in range(30000):
            previous = rng.uniform(0, .95)
            density = 10 ** rng.uniform(-4, 2)
            yield_density = 10 ** rng.uniform(-4, 1)
            rate = 10 ** rng.uniform(-2, 2)
            dt = 10 ** rng.uniform(-4, 0)
            result = evolve(previous, density, yield_density, rate, dt)
            if result is None:
                continue
            increased += 1
            self.assertGreaterEqual(result, previous)
            self.assertLessEqual(result, .95)
            self.assertTrue(math.isfinite(result))
            self.assertGreaterEqual(alpha(1., result), alpha(1., previous))
            self.assertLessEqual(alpha(1., result), 20.0000001)
        self.assertGreater(increased, 2000)

    def test_substeps_at_constant_strain_energy(self):
        rng = random.Random(0xC3E90)
        for _ in range(10000):
            density = 10**rng.uniform(-2, 0)
            yield_density = density * rng.uniform(.3, .9)
            dt = rng.uniform(.01, .2)
            rate = rng.uniform(.01, 2.)
            base = rng.uniform(0, .5)
            full = evolve(base, density, yield_density, rate, dt)
            half = evolve(base, density, yield_density, rate, dt/2)
            half = evolve(half, density, yield_density, rate, dt/2)
            self.assertAlmostEqual(full, half, delta=1e-12)

    def test_no_damage_below_yield_and_overflow_saturation(self):
        self.assertIsNone(evolve(0, .01, .1, 1., .1))
        self.assertIsNone(evolve(0, .1, .1, 1., .1))
        self.assertIsNone(evolve(0, .5, .1, 0., .1))
        self.assertIsNone(evolve(0, .5, .1, 1., 0.))
        self.assertIsNone(evolve(.95, 1., .1, 1., .1))
        self.assertEqual(evolve(0, 1e200, 1e-10, 1000., 2.), .95)
        self.assertEqual(alpha(1., 0.), 1.)
        self.assertAlmostEqual(alpha(1., .95), 20.)

    def test_wiring_and_per_step_no_default_allocations(self):
        fem = (ROOT/"modules/godot_physics_3d/godot_soft_body_3d.cpp").read_text()
        mesh = (ROOT/"servers/physics_fem_convex_star.h").read_text()
        helper = (ROOT/"servers/physics_fem_tetra_damage.h").read_text()
        space = (ROOT/"modules/godot_physics_3d/godot_space_3d.cpp").read_text()
        space_h = (ROOT/"modules/godot_physics_3d/godot_space_3d.h").read_text()
        server = (ROOT/"servers/physics_3d/physics_server_3d.cpp").read_text()
        self.assertIn("double damage = 0.0;", mesh)
        self.assertIn("physics_fem_tetra_accumulate_damage(", helper)
        self.assertIn("physics_fem_tetra_damage_alpha(", helper)
        self.assertIn("physics_fem_tetra_accumulate_damage(energy / tetra.rest.volume,", fem)
        self.assertEqual(fem.count("physics_fem_tetra_damage_alpha("), 2)
        self.assertEqual(fem.count("physics_fem_tetra_accumulate_damage("), 1)
        self.assertLess(fem.index("physics_fem_tetra_accumulate_damage(energy / tetra.rest.volume,"),
                        fem.index("for (int isolve = 0; isolve < iteration_count; ++isolve)"))
        self.assertIn("if (use_fem && fem_damage_rate > real_t(0.0))", fem)
        self.assertIn("get_soft_body_tetra_damage_rate()", fem)
        self.assertIn("get_soft_body_tetra_damage_yield_energy()", fem)
        self.assertIn("real_t soft_body_tetra_damage_rate = 0.0;", space_h)
        self.assertIn('GLOBAL_GET("physics/3d/solver/soft_body_tetra_damage_rate")', space)
        self.assertIn('"physics/3d/solver/soft_body_tetra_damage_rate"', server)
        self.assertIn('"physics/3d/solver/soft_body_tetra_damage_yield_energy"', server)
        self.assertIn("tetra.damage", fem)
        # No extra scratch vectors or per-face buffers: scalar is part of each cooked tet.
        self.assertNotIn("LocalVector<double> xpbd_fem_damage", fem)


if __name__ == "__main__":
    unittest.main()
