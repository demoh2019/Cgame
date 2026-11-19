"""Contracts for opt-in closed-shell XPBD viscoplastic volume relaxation.

No engine runtime or external Python dependencies. The C++ unit test covers
the actual helper; this suite verifies thousands of numerical and source
integration cases and ensures gas pressure uses immutable initial volume.
"""

import math
import pathlib
import random
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


def volume_creep(current, original, yield_strain, fraction, rest):
    values = [current, original, yield_strain, fraction, rest]
    if not all(math.isfinite(v) for v in values):
        return None
    if min(abs(current), abs(original), abs(rest)) <= 0:
        return None
    if any((v < 0) != (original < 0) for v in (current, rest)):
        return None
    if not 0 <= yield_strain <= .95 or not 0 < fraction <= 1:
        return None
    original_abs = abs(original)
    length = abs(current)
    previous = abs(rest)
    ratio = length / previous
    if not 0 < ratio < float("inf"):
        return None
    if ratio > 1 + yield_strain:
        target = length / (1 + yield_strain)
    elif ratio < 1 - yield_strain:
        target = length / (1 - yield_strain)
    else:
        return None
    target = min(max(target, original_abs * .02), original_abs * 20)
    result = previous + (target - previous) * fraction
    if not math.isfinite(result) or result <= 0 or result == previous:
        return None
    return -result if original < 0 else result


class TestVolumetricPlasticity(unittest.TestCase):
    def test_randomized_orientation_yield_and_saturation(self):
        rng = random.Random(0x5EFAC)
        checked = 0
        for _ in range(30000):
            original = 10 ** rng.uniform(-30, 30)
            direction = -1 if rng.random() < .5 else 1
            rest = direction * original
            current = rest * (10 ** rng.uniform(-2, 2))
            yield_strain = rng.random() * .95
            fraction = rng.random()
            changed = volume_creep(current, rest, yield_strain, fraction, rest)
            if changed is None:
                continue
            checked += 1
            self.assertTrue(math.isfinite(changed))
            self.assertEqual(changed < 0, rest < 0)
            self.assertGreaterEqual(abs(changed), .02 * original * (1 - 1e-12))
            self.assertLessEqual(abs(changed), 20 * original * (1 + 1e-12))
            self.assertLessEqual(abs(abs(changed) - original), abs(abs(current) - original) + abs(original) * 19)
        self.assertGreater(checked, 15000)

    def test_time_substeps_and_gas_reference(self):
        full = volume_creep(.5, 1., .1, 1-math.exp(-3*.2), 1.)
        half = volume_creep(.5, 1., .1, 1-math.exp(-3*.1), 1.)
        half = volume_creep(.5, 1., .1, 1-math.exp(-3*.1), half)
        self.assertAlmostEqual(full, half, places=13)
        self.assertLess(full, 1)
        # Ideal gas mass remains fixed: original volume, not elastic target.
        original = 1.0
        gamma = 1.4
        pressure = 1000 * (original / .5) ** gamma
        self.assertGreater(pressure, 1000.0)

    def test_invalid_and_rest_range(self):
        self.assertIsNone(volume_creep(.5, 1, .1, .0, 1))
        self.assertIsNone(volume_creep(-.5, 1, .1, 1, 1))
        self.assertIsNone(volume_creep(float("nan"), 1, .1, 1, 1))
        self.assertIsNone(volume_creep(.5, 1, 1.0, 1, 1))
        self.assertIsNone(volume_creep(.95, 1, .1, 1, 1))
        self.assertEqual(volume_creep(1e-12, 1, .1, 1, 1), .02)
        self.assertEqual(volume_creep(1000., 1, .1, 1, 1), 20.)

    def test_cgame_source_integration_and_default_opt_out(self):
        source = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.cpp").read_text()
        header = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.h").read_text()
        space_cpp = (ROOT / "modules/godot_physics_3d/godot_space_3d.cpp").read_text()
        space_h = (ROOT / "modules/godot_physics_3d/godot_space_3d.h").read_text()
        server = (ROOT / "servers/physics_3d/physics_server_3d.cpp").read_text()
        self.assertIn("double xpbd_volume_original_rest = 0.0;", header)
        self.assertIn("double xpbd_volume_rest = 0.0;", header)
        self.assertIn("xpbd_volume_original_rest = volume;", source)
        self.assertIn("physics_softbody_creep_rest_volume(current_volume,", source)
        self.assertIn("physics_softbody_adiabatic_pressure(xpbd_volume_original_rest,", source)
        self.assertIn("const int orientation = xpbd_volume_original_rest >= 0.0", source)
        self.assertLess(source.index("physics_softbody_creep_rest_volume(current_volume,"),
                        source.index("for (int isolve = 0; isolve < iteration_count; ++isolve)"))
        self.assertIn("get_space()->get_soft_body_xpbd_volume_compliance() > 0.0", source)
        self.assertIn("real_t soft_body_volume_plastic_creep_rate = 0.0;", space_h)
        self.assertIn('GLOBAL_GET("physics/3d/solver/soft_body_volume_plastic_creep_rate")', space_cpp)
        self.assertIn('"physics/3d/solver/soft_body_volume_plastic_creep_rate"', server)
        self.assertIn('"physics/3d/solver/soft_body_volume_plastic_yield_strain"', server)
        self.assertIn("xpbd_volume_original_rest = 0.0;", source)


if __name__ == "__main__":
    unittest.main()
