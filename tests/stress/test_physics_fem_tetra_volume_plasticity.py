"""Reference contracts for local volumetric plasticity of tetrahedral FEM.

The C++ smoke test compiles the REAL Godot helper in float32 / float64.
This Python suite checks random numerical properties and source wiring.
"""

import math
import pathlib
import random
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


def integrate_volume_scale(plastic_scale, current_j, log_yield, fraction):
    if not all(math.isfinite(v) for v in (plastic_scale, current_j, log_yield, fraction)):
        return None
    if not .2 <= plastic_scale <= 5 or current_j <= 1e-9:
        return None
    if not 0 <= log_yield <= 2 or not 0 < fraction <= 1:
        return None
    strain = math.log(current_j)
    if abs(strain) <= log_yield:
        return None
    excess = strain-log_yield if strain > 0 else strain+log_yield
    log_scale = math.log(plastic_scale)
    target_log = min(math.log(5.), max(math.log(.2), log_scale + fraction*excess))
    if abs(target_log-log_scale) <= 1e-14:
        return None
    new_scale = min(5., max(.2, math.exp(target_log)))
    relative = new_scale/plastic_scale
    return new_scale, relative


class TestTetraVolumePlasticity(unittest.TestCase):
    def test_randomized_50000_stable_plastic_changes(self):
        rng = random.Random(0x7E7A)
        changed = 0
        for _ in range(50000):
            previous = rng.uniform(.2, 5.)
            j = 10 ** rng.uniform(-3, 3)
            yield_strain = rng.uniform(0, 2)
            fraction = rng.random()
            change = integrate_volume_scale(previous, j, yield_strain, fraction)
            if change is None:
                continue
            new_scale, relative = change
            changed += 1
            self.assertTrue(math.isfinite(new_scale))
            self.assertTrue(math.isfinite(relative))
            self.assertGreaterEqual(new_scale, .2)
            self.assertLessEqual(new_scale, 5.)
            self.assertGreater(relative, 0.)
            self.assertGreater(relative ** (1./3.), 0.)
            # Rest change pulls log-strain toward zero unless saturated.
            before = math.log(j)
            after = math.log(j / relative)
            self.assertLessEqual(abs(after), abs(before) + 1e-12)
            if before > yield_strain:
                self.assertGreaterEqual(new_scale, previous - 1e-12)
            else:
                self.assertLessEqual(new_scale, previous + 1e-12)
        self.assertGreater(changed, 25000)

    def test_constant_deformation_time_subdivision(self):
        rng = random.Random(0x5A1E)
        for _ in range(10000):
            j = 10 ** rng.uniform(-1.5, 1.5)
            yield_strain = rng.uniform(0, .3)
            rate = rng.uniform(.05, 5.)
            dt = rng.uniform(.001, .3)
            once = integrate_volume_scale(1., j, yield_strain, 1-math.exp(-rate*dt))
            half = integrate_volume_scale(1., j, yield_strain, 1-math.exp(-rate*dt/2))
            if once is None or half is None:
                continue
            # Local J is measured relative to the CHANGED mechanical rest.
            new_scale = half[0]
            second = integrate_volume_scale(new_scale, j / new_scale, yield_strain,
                                           1-math.exp(-rate*dt/2))
            result = second[0] if second else new_scale
            self.assertAlmostEqual(once[0], result, delta=1e-11)

    def test_rigid_motion_elastic_window_and_saturation(self):
        self.assertIsNone(integrate_volume_scale(1., 1., .1, 1.))
        self.assertIsNone(integrate_volume_scale(1., 1.1, .2, 1.))
        self.assertIsNone(integrate_volume_scale(1., -1., .1, 1.))
        self.assertIsNone(integrate_volume_scale(1., 1., .1, 0))
        self.assertIsNone(integrate_volume_scale(1., float("nan"), .1, 1.))
        self.assertEqual(integrate_volume_scale(1., 1000., 0., 1.)[0], 5.)
        self.assertEqual(integrate_volume_scale(1., .001, 0., 1.)[0], .2)

    def test_source_uses_one_step_and_preserves_original_gas_and_mass(self):
        c = (ROOT/"modules/godot_physics_3d/godot_soft_body_3d.cpp").read_text()
        s = (ROOT/"modules/godot_physics_3d/godot_space_3d.cpp").read_text()
        sh = (ROOT/"modules/godot_physics_3d/godot_space_3d.h").read_text()
        server = (ROOT/"servers/physics_3d/physics_server_3d.cpp").read_text()
        cooked = (ROOT/"servers/physics_fem_convex_star.h").read_text()
        helper = (ROOT/"servers/physics_fem_tetra_volume_plasticity.h").read_text()
        self.assertEqual(c.count("physics_fem_tetra_creep_volume_rest("), 1)
        self.assertIn("PhysicsFEMTetraRest candidate = r_rest;", helper)
        self.assertIn("candidate.inv_dm[i][j] /= linear_factor;", helper)
        self.assertIn("candidate.volume *= relative_volume;", helper)
        self.assertIn("candidate.signed_det *= relative_volume;", helper)
        self.assertIn("double plastic_volume_scale = 1.0;", cooked)
        self.assertLess(c.index("physics_fem_tetra_creep_volume_rest("),
                        c.index("for (int isolve = 0; isolve < iteration_count; ++isolve)"))
        self.assertIn("tetra_plastic_rate > real_t(0.0)", c)
        self.assertIn("get_soft_body_tetra_fem_compliance() > real_t(0.0)", c)
        self.assertIn("tetra.rest, tetra.plastic_volume_scale", c)
        self.assertIn("physics_softbody_adiabatic_pressure(xpbd_volume_original_rest,", c)
        self.assertIn("physics_fem_build_lumped_masses(", c)
        self.assertIn("real_t soft_body_tetra_volume_plastic_rate = 0.0;", sh)
        self.assertIn('GLOBAL_GET("physics/3d/solver/soft_body_tetra_volume_plastic_rate")', s)
        self.assertIn('"physics/3d/solver/soft_body_tetra_volume_plastic_rate"', server)
        self.assertIn('"physics/3d/solver/soft_body_tetra_volume_plastic_yield"', server)


if __name__ == "__main__":
    unittest.main()
