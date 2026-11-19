"""Analytical and source contracts for pressure-driven sealed SoftBody gas leaks.

This tests the simplified mass-decay model independently of the native helper.
It does not establish that the actual engine compiles or passes runtime tests.
"""
import math
import random
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def vent_step(mass, reference_volume, volume, pressure_at_rest, gamma, rate, delta):
    if not all(map(math.isfinite, (mass, reference_volume, volume,
                                   pressure_at_rest, gamma, rate, delta))):
        raise ValueError("nonfinite")
    if not (0 <= mass <= 1 and rate >= 0 and delta >= 0 and
            reference_volume * volume > 0 and pressure_at_rest > 0 and 0 < gamma <= 5):
        raise ValueError("invalid")
    relative_volume = abs(volume / reference_volume)
    if relative_volume <= 0:
        raise ValueError("degenerate")
    sealed = pressure_at_rest * max(relative_volume, .05) ** (-gamma)
    before = sealed * mass ** gamma
    if rate and delta and mass and before:
        speed = math.sqrt(min(before / pressure_at_rest, 1e12))
        mass *= math.exp(-min(rate * delta * speed, 750))
    return mass, sealed * mass ** gamma


class SoftBodyGasLeakTests(unittest.TestCase):
    def test_reference_zero_leak_preserves_existing_eos(self):
        for gamma in (1.0, 1.4, 2.0, 5.0):
            for volume in (0.05, 0.1, 1., 4.):
                mass, pressure = vent_step(1., 1., volume, 100., gamma, 0., 0.1)
                self.assertEqual(mass, 1.)
                self.assertAlmostEqual(pressure, 100. * max(volume, .05) ** (-gamma))

    def test_exponential_isothermal_mass_discharge(self):
        mass, pressure = vent_step(1., 1., 1., 100., 1., 1., 1.)
        self.assertAlmostEqual(mass, math.exp(-1.))
        self.assertAlmostEqual(pressure, 100.*math.exp(-1.))

    def test_compressed_shell_leaks_faster(self):
        rng = random.Random(20261119)
        for _ in range(10000):
            gamma = rng.uniform(1., 2.)
            rate = rng.uniform(0.001, 5.)
            delta = rng.uniform(0.001, .1)
            compressed, _ = vent_step(1., 1., .5, 100., gamma, rate, delta)
            expanded, _ = vent_step(1., 1., 2., 100., gamma, rate, delta)
            self.assertLess(compressed, expanded)

    def test_random_finite_nonincreasing_mass_and_pressure(self):
        rng = random.Random(991)
        for _ in range(10000):
            m0 = rng.uniform(0., 1.)
            gamma = rng.uniform(.1, 5.)
            rate = 10 ** rng.uniform(-3, 3)
            delta = 10 ** rng.uniform(-4, 1)
            volume = 10 ** rng.uniform(-4, 4)
            new_m, new_p = vent_step(m0, 1., volume, 100., gamma, rate, delta)
            self.assertLessEqual(new_m, m0)
            self.assertGreaterEqual(new_m, 0.)
            self.assertGreaterEqual(new_p, 0.)
            self.assertTrue(math.isfinite(new_p))

    def test_zero_mass_zero_step_and_inverted_geometry(self):
        self.assertEqual(vent_step(0., 1., 1., 100., 1.4, 5., .1), (0., 0.))
        self.assertEqual(vent_step(1., 1., 1., 100., 1.4, 5., 0.), (1., 100.))
        with self.assertRaises(ValueError):
            vent_step(1., 1., -1., 100., 1.4, 1., .1)

    def test_native_source_and_reset_contracts(self):
        helper = (ROOT / "servers/physics_softbody_gas_leak.h").read_text()
        cpp = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.cpp").read_text()
        header = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.h").read_text()
        space = (ROOT / "modules/godot_physics_3d/godot_space_3d.cpp").read_text()
        space_h = (ROOT / "modules/godot_physics_3d/godot_space_3d.h").read_text()
        settings = (ROOT / "servers/physics_3d/physics_server_3d.cpp").read_text()
        self.assertIn("physics_softbody_adiabatic_pressure(", helper)
        self.assertIn("const double previous_pressure = sealed_pressure * Math::pow(", helper)
        self.assertIn("Math::exp(-exponent)", helper)
        self.assertIn("const double pressure_ratio = previous_pressure / p_pressure_at_rest;", helper)
        self.assertIn("r_mass_fraction = next_mass;", helper)
        self.assertIn("r_pressure = next_pressure;", helper)
        self.assertLess(helper.index("const double next_pressure"), helper.index("r_mass_fraction = next_mass;"))
        self.assertIn("double gas_mass_fraction = 1.0;", header)
        self.assertIn("gas_mass_fraction = 1.0;", cpp)
        self.assertIn("physics_softbody_gas_leak_step(xpbd_volume_rest, signed_volume,", cpp)
        self.assertIn("get_soft_body_gas_leak_rate()", cpp)
        self.assertIn("soft_body_gas_leak_rate", space)
        self.assertIn("get_soft_body_gas_leak_rate()", space_h)
        self.assertIn('"physics/3d/solver/soft_body_gas_leak_rate"', settings)
        self.assertIn('"0,100,0.1,or_greater,suffix:1/s"), 0.0);', settings)

    def test_native_and_runtime_registration(self):
        native = (ROOT / "tests/servers/test_physics_softbody_gas_leak.cpp").read_text()
        self.assertIn("TEST_FORCE_LINK(test_physics_softbody_gas_leak)", native)
        self.assertEqual(native.count('TEST_CASE("[PhysicsGasLeak]'), 7)
        workflow = (ROOT / ".github/workflows/whole-engine-stress.yml").read_text()
        self.assertIn("*[PhysicsGasLeak]*", workflow)
        stress = (ROOT / "tests/stress/physics_softbody_gas_leak_3d_regression.gd").read_text()
        self.assertIn("soft_body_set_pressure_coefficient(", stress)
        self.assertIn("leak_rate", stress)
        self.assertIn("sealed_volume > vented_volume", stress)


if __name__ == "__main__":
    unittest.main()
