"""Analytic J2-like deviatoric Hencky-plasticity reference and source contracts.

Standalone GitHub Actions C++ smoke compiles the production header itself
with -Werror in float32 and float64. This suite checks invariant algebra.
"""

import math
import pathlib
import random
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


def creep_principal(log_sigma, yield_eq, fraction, remaining_budget):
    mean = sum(log_sigma)/3.
    dev = tuple(e - mean for e in log_sigma)
    eq = math.sqrt((2./3.)*sum(e*e for e in dev))
    if eq <= yield_eq or remaining_budget <= 0:
        return None
    added = min(fraction*(eq-yield_eq), remaining_budget)
    if added <= 1e-14:
        return None
    new = tuple(e-d*added/eq for e, d in zip(log_sigma, dev))
    return new, added, eq


def dot(a, b):
    return sum(x*y for x, y in zip(a, b))


class TestFEMDeviatoricPlasticity(unittest.TestCase):
    def test_50000_random_principal_stretches_preserve_volume(self):
        rng = random.Random(0xDEB105)
        successes = 0
        for _ in range(50000):
            stretches = tuple(10 ** rng.uniform(-.8, .8) for _ in range(3))
            logs = tuple(math.log(s) for s in stretches)
            yield_eq = rng.uniform(0, .2)
            fraction = rng.random()
            remaining = rng.uniform(.01, 4.)
            output = creep_principal(logs, yield_eq, fraction, remaining)
            if output is None:
                continue
            updated, delta, eq = output
            successes += 1
            mean_after = sum(updated)/3.
            eq_after = math.sqrt(2./3.*sum((q-mean_after)**2 for q in updated))
            self.assertAlmostEqual(sum(updated), sum(logs), delta=1e-11)
            self.assertAlmostEqual(eq_after, eq-delta, delta=1e-10)
            self.assertGreaterEqual(eq_after, -1e-11)
            self.assertGreaterEqual(delta, 0.)
            self.assertLessEqual(delta, remaining+1e-12)
        self.assertGreater(successes, 45000)

    def test_rigid_rotation_invariance_of_right_metric(self):
        rng = random.Random(0xAABB)
        for _ in range(2000):
            # Nontrivial deformation gradient, composed with global Z rotation.
            shear = rng.uniform(-1.5, 1.5)
            f = ((1., shear, 0.), (0., 1., 0.), (0., 0., 1.))
            angle = rng.uniform(-math.pi, math.pi)
            c, s = math.cos(angle), math.sin(angle)
            R = ((c,-s,0.), (s,c,0.), (0.,0.,1.))
            rotated = tuple(tuple(sum(R[i][k]*f[k][j] for k in range(3))
                                 for j in range(3)) for i in range(3))
            metric = tuple(tuple(sum(f[k][i]*f[k][j] for k in range(3))
                                 for j in range(3)) for i in range(3))
            metric_rot = tuple(tuple(sum(rotated[k][i]*rotated[k][j]
                                         for k in range(3)) for j in range(3))
                               for i in range(3))
            for i in range(3):
                for j in range(3):
                    self.assertAlmostEqual(metric[i][j], metric_rot[i][j], delta=1e-12)

    def test_rate_time_subdivision_consistency(self):
        rng = random.Random(0xBEEF)
        for _ in range(10000):
            principal_logs = (rng.uniform(.3, 1.), rng.uniform(-.8, -.1), rng.uniform(-.2, .2))
            yield_eq = rng.uniform(.01, .15)
            rate = rng.uniform(.1, 6.)
            dt = rng.uniform(.01, .3)
            once = creep_principal(principal_logs, yield_eq, 1-math.exp(-rate*dt), 4.)
            half = creep_principal(principal_logs, yield_eq, 1-math.exp(-rate*dt/2), 4.)
            if once is None or half is None:
                continue
            second = creep_principal(half[0], yield_eq, 1-math.exp(-rate*dt/2),
                                     4.-half[1])
            if second is None:
                continue
            for a, b in zip(once[0], second[0]):
                self.assertAlmostEqual(a, b, delta=1e-11)

    def test_no_plasticity_for_hydrostatic_or_below_yield_strain(self):
        for length in (.2, 1., 5.):
            logs = tuple(math.log(length) for _ in range(3))
            self.assertIsNone(creep_principal(logs, .01, 1., 2.))
        self.assertIsNone(creep_principal((.1, -.1, 0.), 2., 1., 4.))
        self.assertIsNone(creep_principal((.1, -.1, 0.), 0., 1., 0.))

    def test_source_wiring_and_hard_limits(self):
        body = (ROOT/"modules/godot_physics_3d/godot_soft_body_3d.cpp").read_text()
        sh = (ROOT/"modules/godot_physics_3d/godot_space_3d.h").read_text()
        space = (ROOT/"modules/godot_physics_3d/godot_space_3d.cpp").read_text()
        settings = (ROOT/"servers/physics_3d/physics_server_3d.cpp").read_text()
        tet = (ROOT/"servers/physics_fem_convex_star.h").read_text()
        helper = (ROOT/"servers/physics_fem_tetra_deviatoric_plasticity.h").read_text()
        self.assertEqual(body.count("physics_fem_tetra_creep_deviatoric_rest("), 1)
        self.assertIn("const double determinant =", helper)
        self.assertIn("metric[row][col] += f[k][row] * f[k][col];", helper)
        self.assertIn("const double equivalent = std::sqrt((2.0 / 3.0) * norm_sq);", helper)
        self.assertIn("candidate.inv_dm[row][col] = value;", helper)
        self.assertIn("std::abs(det - 1.0) > 1e-8", helper)
        self.assertIn("PhysicsFEMTetraRest candidate = r_rest;", helper)
        self.assertIn("double plastic_deviatoric_strain = 0.0;", tet)
        self.assertIn("tetra.rest, tetra.plastic_deviatoric_strain", body)
        self.assertIn("soft_body_tetra_shear_plastic_rate = 0.0;", sh)
        self.assertIn('GLOBAL_GET("physics/3d/solver/soft_body_tetra_shear_plastic_rate")', space)
        self.assertIn('"physics/3d/solver/soft_body_tetra_shear_plastic_rate"', settings)
        self.assertLess(body.index("physics_fem_tetra_creep_deviatoric_rest("),
                        body.index("for (int isolve = 0; isolve < iteration_count; ++isolve)"))
        self.assertIn("physics_fem_tetra_creep_volume_rest(", body)
        self.assertIn("physics_fem_tetra_mooney_rivlin_solve(", body)
        self.assertIn("physics_fem_tetra_ogden_solve(", body)
        self.assertIn("physics_fem_tetra_solve_fiber(", body)


if __name__ == "__main__":
    unittest.main()
