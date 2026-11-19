"""Source and reference-model regressions for opt-in SoftBody3D viscoplasticity.

Run with: python3 -m unittest discover -s tests/stress -p test_physics_softbody_plasticity.py -v
Native TEST_CASEs require a Cgame tests=yes build.
"""

import math
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


def creep_rest_length(length, rest, yield_strain, rate, dt):
    if rate <= 0 or length <= 0 or rest <= 0 or not (0 <= yield_strain <= 1):
        return rest
    factor = 1 - math.exp(-rate * dt)
    if length > rest * (1 + yield_strain):
        target = length / (1 + yield_strain)
    elif yield_strain < 1 and length < rest * (1 - yield_strain):
        target = length / (1 - yield_strain)
    else:
        return rest
    return rest + (target - rest) * factor


class SoftBodyPlasticityContracts(unittest.TestCase):
    def test_elastic_range_does_not_permanently_change_rest_length(self):
        self.assertEqual(creep_rest_length(1.05, 1.0, 0.1, 10.0, 1.0), 1.0)
        self.assertEqual(creep_rest_length(1.5, 1.0, 0.1, 0.0, 1.0), 1.0)

    def test_tensile_and_compressive_plasticity(self):
        a = creep_rest_length(1.5, 1.0, 0.1, 1000.0, 1.0)
        b = creep_rest_length(1.0, 2.0, 0.2, 1000.0, 1.0)
        self.assertAlmostEqual(a, 1.5 / 1.1)
        self.assertAlmostEqual(b, 1.0 / 0.8)

    def test_exponential_rate_independence_under_constant_strain(self):
        whole = creep_rest_length(1.8, 1.0, 0.1, 1.0, 1.0)
        half = creep_rest_length(1.8, 1.0, 0.1, 1.0, 0.5)
        half = creep_rest_length(1.8, half, 0.1, 1.0, 0.5)
        self.assertAlmostEqual(whole, half, places=6)

    def test_both_project_settings_are_opt_in(self):
        cpp = (ROOT / "servers/physics_3d/physics_server_3d.cpp").read_text()
        for setting in ("soft_body_plastic_yield_strain", "soft_body_plastic_creep_rate"):
            self.assertIn(f'physics/3d/solver/{setting}', cpp)
        self.assertIn('"physics/3d/solver/soft_body_plastic_yield_strain",', cpp)
        self.assertIn('"physics/3d/solver/soft_body_plastic_creep_rate",', cpp)
        space = (ROOT / "modules/godot_physics_3d/godot_space_3d.h").read_text()
        self.assertIn("soft_body_plastic_creep_rate = 0.0", space)
        self.assertIn("get_soft_body_plastic_yield_strain()", space)

    def test_solver_applies_plasticity_to_predicted_positions_before_constraints(self):
        src = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.cpp").read_text()
        self.assertIn('#include "servers/physics_softbody_plasticity.h"', src)
        self.assertIn("physics_softbody_creep_rest_length(", src)
        self.assertIn("link.c1 = link.rl * link.rl;", src)
        pre = src.index("const real_t plastic_creep_rate =")
        xpbd = src.index("const real_t configured_compliance =", pre)
        self.assertLess(pre, xpbd)
        self.assertIn("1.0 - Math::exp(-double(plastic_creep_rate) * double(p_delta))", src)

    def test_helper_rejects_bad_squared_rest_length(self):
        src = (ROOT / "servers/physics_softbody_plasticity.h").read_text()
        self.assertIn("!(squared_rest_length > real_t(0.0))", src)
        self.assertIn("!Math::is_finite(squared_rest_length)", src)
        self.assertIn("next_rest_length == r_rest_length", src)
        native = (ROOT / "tests/servers/test_physics_softbody_plasticity.cpp").read_text()
        self.assertEqual(native.count('TEST_CASE("[PhysicsPlasticity]'), 6)


if __name__ == "__main__":
    unittest.main()
