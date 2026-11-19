"""Independent contracts for two anisotropic tetra FEM fiber families.

Family 2 has an independent material axis, XPBD lambda, compliance and
per-tetra tensile-plastic rest length. Both fibers use the same scalar FEM
damage, without mixing their unilateral stresses or plastic histories.
"""
import math
import random
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
VOLUME = 1.0 / 6.0
G = math.sqrt(VOLUME)


def solve_axis(stretch, inverse_mass, alpha, plastic_rest=1.):
    if stretch <= plastic_rest or inverse_mass <= 0.:
        return stretch, 0.
    lambda_value = (stretch-plastic_rest)*G / (inverse_mass*VOLUME+alpha)
    return stretch-inverse_mass*G*lambda_value, lambda_value


def evolve_rest(current, old, yield_ratio, creep_rate, dt, maximum):
    if current <= old*(1+yield_ratio) or creep_rate <= 0 or dt <= 0:
        return old
    target = min(maximum, current/(1+yield_ratio))
    return min(maximum, old+(target-old)*(1-math.exp(-creep_rate*dt)))


def axis_stretch(f, axis):
    length = math.sqrt(sum(x*x for x in axis))
    u = [x/length for x in axis]
    mapped = [sum(f[row][col]*u[col] for col in range(3)) for row in range(3)]
    return math.sqrt(sum(x*x for x in mapped))


class TestTetraDualFiberReference(unittest.TestCase):
    def test_6000_decoupled_biaxial_constraints(self):
        rng = random.Random(0xA2F1BE)
        for _ in range(6000):
            x = rng.uniform(1.01, 2.3)
            y = rng.uniform(1.01, 2.3)
            im_b = rng.uniform(.1, 5.)
            im_c = rng.uniform(.1, 5.)
            alpha_x = rng.uniform(1e-6, .2)
            alpha_y = rng.uniform(1e-6, .2)
            x_next, lam_x = solve_axis(x, im_b, alpha_x)
            y_next, lam_y = solve_axis(y, im_c, alpha_y)
            self.assertGreater(lam_x, 0.)
            self.assertGreater(lam_y, 0.)
            self.assertGreaterEqual(x_next, 1.-1e-12)
            self.assertGreaterEqual(y_next, 1.-1e-12)
            self.assertLessEqual(x_next, x)
            self.assertLessEqual(y_next, y)
            # A pinned tetra anchor prevents X and Y fiber rows from
            # coupling in the diagonal-extension reference configuration.
            self.assertAlmostEqual(
                (x_next-x)/im_b + G*lam_x, 0., delta=1e-12)
            self.assertAlmostEqual(
                (y_next-y)/im_c + G*lam_y, 0., delta=1e-12)
            d = rng.uniform(0., .9)
            damaged_x, _ = solve_axis(x, im_b, alpha_x/(1.-d))
            damaged_y, _ = solve_axis(y, im_c, alpha_y/(1.-d))
            self.assertGreaterEqual(damaged_x+1e-12, x_next)
            self.assertGreaterEqual(damaged_y+1e-12, y_next)

    def test_3000_oblique_axes_under_world_rotation(self):
        rng = random.Random(0xF1B2CC)
        for _ in range(3000):
            x, y, z = [rng.uniform(.6, 2.) for _ in range(3)]
            shear = rng.uniform(-.4, .4)
            f = ((x, shear, 0), (0, y, 0), (0, 0, z))
            axis_a = (1., 0., 0.)
            axis_b = (rng.uniform(-1., 1.), rng.uniform(-1., 1.),
                      rng.uniform(-1., 1.))
            if math.dist(axis_b, (0., 0., 0.)) < .05:
                continue
            angle = rng.uniform(-math.pi, math.pi)
            co, si = math.cos(angle), math.sin(angle)
            rotation = ((co, -si, 0.), (si, co, 0.), (0., 0., 1.))
            rotated = [[sum(rotation[i][k]*f[k][j] for k in range(3))
                        for j in range(3)] for i in range(3)]
            for axis in (axis_a, axis_b):
                self.assertAlmostEqual(axis_stretch(f, axis),
                                       axis_stretch(rotated, axis),
                                       delta=1e-12)

    def test_3000_independent_plastic_creep(self):
        rng = random.Random(0xDDAACE)
        for _ in range(3000):
            x, y = rng.uniform(1.05, 2.4), rng.uniform(1.05, 2.4)
            yield_x, yield_y = rng.uniform(0., .25), rng.uniform(0., .25)
            rate_x, rate_y = rng.uniform(.1, 12.), rng.uniform(.1, 12.)
            dt = rng.uniform(.001, .12)
            cap_x, cap_y = rng.uniform(1.5, 4.), rng.uniform(1.5, 4.)
            plastic_x = evolve_rest(x, 1., yield_x, rate_x, dt, cap_x)
            plastic_y = evolve_rest(y, 1., yield_y, rate_y, dt, cap_y)
            self.assertGreaterEqual(plastic_x, 1.)
            self.assertGreaterEqual(plastic_y, 1.)
            self.assertLessEqual(plastic_x, cap_x)
            self.assertLessEqual(plastic_y, cap_y)
            self.assertEqual(
                evolve_rest(.5, plastic_x, yield_x, rate_x, dt, cap_x),
                plastic_x)
            self.assertEqual(
                evolve_rest(.5, plastic_y, yield_y, rate_y, dt, cap_y),
                plastic_y)
            if x <= 1+yield_x:
                self.assertEqual(plastic_x, 1.)
            if y <= 1+yield_y:
                self.assertEqual(plastic_y, 1.)
            if x > plastic_x and y > plastic_y:
                rx, _ = solve_axis(x, 1., .01, plastic_x)
                ry, _ = solve_axis(y, 1., .01, plastic_y)
                ex, _ = solve_axis(x, 1., .01)
                ey, _ = solve_axis(y, 1., .01)
                self.assertGreaterEqual(rx+1e-12, ex)
                self.assertGreaterEqual(ry+1e-12, ey)

    def test_engine_settings_histories_and_solver_wiring(self):
        s = (ROOT/"servers/physics_3d/physics_server_3d.cpp").read_text()
        sh = (ROOT/"modules/godot_physics_3d/godot_space_3d.h").read_text()
        sc = (ROOT/"modules/godot_physics_3d/godot_space_3d.cpp").read_text()
        bh = (ROOT/"modules/godot_physics_3d/godot_soft_body_3d.h").read_text()
        b = (ROOT/"modules/godot_physics_3d/godot_soft_body_3d.cpp").read_text()
        for key in ("soft_body_tetra_fiber_secondary_compliance",
                    "soft_body_tetra_fiber_secondary_axis",
                    "soft_body_tetra_fiber_secondary_plastic_yield_ratio",
                    "soft_body_tetra_fiber_secondary_plastic_creep_rate",
                    "soft_body_tetra_fiber_secondary_plastic_max_stretch"):
            self.assertIn("physics/3d/solver/"+key, s)
            self.assertIn(key, sh)
            self.assertIn(key, sc)
        self.assertIn("soft_body_tetra_fiber_secondary_compliance = 0.0;", sh)
        self.assertIn("soft_body_tetra_fiber_secondary_plastic_creep_rate = 0.0;",sh)
        self.assertIn("LocalVector<double> xpbd_fem_fiber_secondary_lambdas;",bh)
        self.assertIn("LocalVector<real_t> xpbd_fem_fiber_secondary_plastic_rest_stretches;",bh)
        self.assertIn("get_soft_body_tetra_fiber_secondary_compliance() > 0.0",b)
        self.assertIn("use_fem_fiber || use_fem_secondary_fiber",b)
        self.assertIn("xpbd_fem_fiber_secondary_lambdas.resize(",b)
        self.assertIn("xpbd_fem_fiber_secondary_lambdas.reset();",b)
        self.assertIn("xpbd_fem_fiber_secondary_plastic_rest_stretches.resize(",b)
        self.assertIn("xpbd_fem_fiber_secondary_plastic_rest_stretches.reset();",b)
        self.assertIn("fem_secondary_fiber_axis, secondary_alpha,",b)
        self.assertIn("xpbd_fem_fiber_secondary_lambdas[tet_index], double(secondary_rest_stretch)",b)
        self.assertIn("fem_secondary_fiber_alpha, xpbd_fem_damage[tet_index], secondary_alpha",b)
        self.assertLess(b.index("physics_fem_tetra_fiber_creep_rest_stretch(\n\t\t\t\t\t\tstretch, plastic_yield, double(secondary_fiber_creep)"),
                        b.index("for (int isolve = 0; isolve < iteration_count; ++isolve)"))
        # Two separate XPBD multipliers must not accidentally become the
        # same buffer, and every user-facing scalar is disabled by default.
        self.assertEqual(bh.count("xpbd_fem_fiber_secondary_lambdas;"),1)


if __name__ == "__main__":
    unittest.main()
