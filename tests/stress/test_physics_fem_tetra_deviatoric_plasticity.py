"""Independent numerical contracts for isochoric tetrahedral plastic FEM.

The implementation uses a symmetric eigen-decomposition of C=F.T F and
changes the material inverse-rest matrix to remove the accumulated
DEVIATORIC logarithmic strain. This reference checks principal
invariants without depending on the compiled Godot engine.
"""
from pathlib import Path
import math
import random
import unittest

ROOT = Path(__file__).resolve().parents[2]


def deviatoric(log_principal):
    mean = sum(log_principal) / 3.
    dev = tuple(v-mean for v in log_principal)
    equivalent = math.sqrt(2./3. * sum(v*v for v in dev))
    return dev, equivalent


def plastic_rate_factor(rate, delta, hardening):
    return (1. - math.exp(-rate * delta * (1.+hardening))) / (1.+hardening)


def one_step(log_principal, accumulated, yield_strain, hardening, factor, cap):
    dev, equivalent = deviatoric(log_principal)
    surplus = equivalent - yield_strain - hardening*accumulated
    # Match the C++ 1e-12 guard for roundoff-only rigid/volumetric strain.
    if surplus <= 1e-12:
        return log_principal, accumulated
    plastic_step = max(0., min(equivalent, cap-accumulated, surplus*factor))
    if plastic_step <= 0:
        return log_principal, accumulated
    beta = plastic_step/equivalent
    new_logs = tuple(v-beta*d for v,d in zip(log_principal, dev))
    return new_logs, accumulated+plastic_step


def principal_logs_for_xy_shear(ax, shear, by, cz):
    # F = [[ax, shear, 0], [0, by, 0], [0, 0, cz]].
    aa = ax*ax
    bb = ax*shear
    dd = shear*shear + by*by
    center = .5*(aa+dd)
    radius = math.sqrt(.25*(aa-dd)**2 + bb*bb)
    values = (center+radius, center-radius, cz*cz)
    if min(values) <= 0:
        return None
    return tuple(.5*math.log(v) for v in values)


class TestTetraDeviatoricPlasticity(unittest.TestCase):
    def test_4000_random_isocoric_plastic_flows(self):
        rng = random.Random(0xD3F02A)
        for _ in range(4000):
            stretch = [rng.uniform(.5, 2.3) for _ in range(3)]
            logs = tuple(math.log(x) for x in stretch)
            old_volume = math.exp(sum(logs))
            damage_yield = rng.uniform(0., .3)
            hardening = rng.uniform(0., 3.)
            plastic_history = rng.uniform(0., .12)
            cap = rng.uniform(.5, 4.)
            factor = plastic_rate_factor(rng.uniform(.1, 20.), rng.uniform(.001, .1), hardening)
            new_logs, new_history = one_step(
                logs, plastic_history, damage_yield, hardening, factor, cap)
            self.assertGreaterEqual(new_history+1e-12, plastic_history)
            self.assertLessEqual(new_history, cap+1e-12)
            self.assertAlmostEqual(math.exp(sum(new_logs)), old_volume, delta=1e-11)
            before_dev, before_eq = deviatoric(logs)
            after_dev, after_eq = deviatoric(new_logs)
            self.assertLessEqual(after_eq, before_eq+1e-12)
            self.assertAlmostEqual(before_eq-after_eq,
                                   new_history-plastic_history, delta=1e-11)
            self.assertTrue(all(math.isfinite(x) for x in new_logs))

    def test_3000_rotated_shear_and_pure_volume_objectivity(self):
        rng = random.Random(0xA91F)
        for _ in range(3000):
            ax, by, cz = (rng.uniform(.6, 2.) for _ in range(3))
            shear = rng.uniform(-.7, .7)
            # Left rotation Q*F must leave C=F.T F unchanged.
            angle = rng.uniform(-math.pi, math.pi)
            c,s = math.cos(angle),math.sin(angle)
            # QR product F, Q rotates the first two world rows.
            f00, f01 = c*ax, c*shear-s*by
            f10, f11 = s*ax, s*shear+c*by
            old = principal_logs_for_xy_shear(ax, shear, by, cz)
            aa = f00*f00+f10*f10
            bb = f00*f01+f10*f11
            dd = f01*f01+f11*f11
            mid = .5*(aa+dd)
            radius = math.sqrt(.25*(aa-dd)**2+bb*bb)
            rotated = tuple(.5*math.log(v) for v in
                            (mid+radius,mid-radius,cz*cz))
            for before,after in zip(old,rotated):
                self.assertAlmostEqual(before, after, delta=1e-11)
            vol = rng.uniform(.6,1.7)
            pure = tuple(math.log(vol) for _ in range(3))
            self.assertEqual(one_step(pure, 0., 0., 0., .8, 4.)[1], 0.)

    def test_1000_hardening_substep_consistency(self):
        rng = random.Random(0xDEC0DE)
        for _ in range(1000):
            logs0 = tuple(math.log(rng.uniform(.5, 2.)) for _ in range(3))
            yield_strain = rng.uniform(0., .2)
            hardening = rng.uniform(0., 3.)
            rate = rng.uniform(.1, 20.)
            duration = rng.uniform(.002, .5)
            cap = 4.
            full_factor = plastic_rate_factor(rate, duration, hardening)
            full_logs,full_history=one_step(logs0,0.,yield_strain,hardening,full_factor,cap)
            sub_logs,sub_history=logs0,0.
            factor=plastic_rate_factor(rate,duration/25.,hardening)
            for _ in range(25):
                sub_logs,sub_history=one_step(sub_logs,sub_history,yield_strain,hardening,factor,cap)
            self.assertAlmostEqual(full_history, sub_history, delta=1e-11)
            for a,b in zip(full_logs,sub_logs):
                self.assertAlmostEqual(a,b,delta=1e-11)

    def test_engine_settings_lifecycle_and_objective_flow(self):
        soft = (ROOT/"modules/godot_physics_3d/godot_soft_body_3d.cpp").read_text()
        soft_h = (ROOT/"modules/godot_physics_3d/godot_soft_body_3d.h").read_text()
        space_h = (ROOT/"modules/godot_physics_3d/godot_space_3d.h").read_text()
        space_cpp = (ROOT/"modules/godot_physics_3d/godot_space_3d.cpp").read_text()
        server = (ROOT/"servers/physics_3d/physics_server_3d.cpp").read_text()
        helper = (ROOT/"servers/physics_fem_tetra_deviatoric_plasticity.h").read_text()
        self.assertIn("soft_body_tetra_deviatoric_plastic_rate = 0.0;", space_h)
        self.assertIn("soft_body_tetra_deviatoric_plastic_rate = Math::is_finite(",space_cpp)
        self.assertIn('"physics/3d/solver/soft_body_tetra_deviatoric_plastic_yield"',server)
        self.assertIn('"physics/3d/solver/soft_body_tetra_deviatoric_plastic_hardening"',server)
        self.assertIn("LocalVector<double> xpbd_fem_deviatoric_plastic_strain;",soft_h)
        self.assertIn("xpbd_fem_deviatoric_plastic_strain.reset();",soft)
        self.assertIn("xpbd_fem_deviatoric_plastic_strain.resize(",soft)
        self.assertIn("physics_fem_tetra_creep_deviatoric_rest(",soft)
        self.assertIn("1.0 - Math::exp(",soft)
        self.assertIn("const double next_accumulated =", helper)
        self.assertIn("r_rest = candidate;",helper)
        self.assertIn("r_accumulated = next_accumulated;",helper)
        self.assertIn("std::cbrt(ratio)",helper)
        self.assertLess(soft.index("physics_fem_tetra_creep_deviatoric_rest("),
                        soft.index("for (int isolve = 0; isolve < iteration_count; ++isolve)"))
        self.assertLess(soft.index("physics_fem_tetra_creep_volume_rest("),
                        soft.index("physics_fem_tetra_creep_deviatoric_rest("))


if __name__ == "__main__":
    unittest.main()
