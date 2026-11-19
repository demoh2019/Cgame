"""Opt-in tetrahedral FEM progressive damage: numerical and source contracts.

The Green-Lagrange norm is objective, triggers shear/compression/tension
and feeds irreversible, exponentially integrated compliance softening.
The reference model is independent of C++ implementation and never
claims full engine compilation.
"""
from pathlib import Path
import math
import random
import unittest

ROOT = Path(__file__).resolve().parents[2]


def strain_from_f(f):
    """F row-major, positive determinant; sqrt(2/3 * E:E)."""
    det = (
        f[0][0] * (f[1][1]*f[2][2] - f[1][2]*f[2][1])
        - f[0][1] * (f[1][0]*f[2][2] - f[1][2]*f[2][0])
        + f[0][2] * (f[1][0]*f[2][1] - f[1][1]*f[2][0])
    )
    if det <= 1e-9 or not math.isfinite(det):
        return None
    e2 = 0.
    for i in range(3):
        for j in range(3):
            cij = sum(f[k][i]*f[k][j] for k in range(3))
            e = .5*(cij - (1. if i == j else 0.))
            e2 += e*e
    return math.sqrt(2./3.*e2)


def evolve(damage, strain, yield_strain, rate, dt, maximum):
    if (not math.isfinite(strain) or strain <= yield_strain or
            rate <= 0 or dt <= 0 or maximum <= 0 or
            maximum > .95 or not 0 <= damage <= maximum):
        return damage
    excess = strain - yield_strain
    severity = excess / (1. + excess)
    fraction = 1. - math.exp(-rate*dt*severity)
    return min(maximum, damage + (maximum-damage)*fraction)


def apply_rotation_left(rot, f):
    return [[sum(rot[i][k]*f[k][j] for k in range(3))
             for j in range(3)] for i in range(3)]


class TetraDamageContracts(unittest.TestCase):
    def test_6000_randomized_objectivity_and_monotonicity(self):
        rng = random.Random(0xDAAA613)
        for _ in range(6000):
            # Positive-J triangular stretch/shear with arbitrary pose.
            sx, sy, sz = (rng.uniform(.55, 1.8) for i in range(3))
            shear = rng.uniform(-.65, .65)
            f = [[sx, shear, 0.], [0., sy, 0.], [0., 0., sz]]
            original = strain_from_f(f)
            self.assertIsNotNone(original)
            theta = rng.uniform(-math.pi, math.pi)
            cs, sn = math.cos(theta), math.sin(theta)
            rotation = [[cs, -sn, 0.], [sn, cs, 0.], [0., 0., 1.]]
            transformed = strain_from_f(apply_rotation_left(rotation, f))
            self.assertAlmostEqual(original, transformed, delta=1e-12)
            threshold = rng.uniform(0., .3)
            rate, dt = rng.uniform(.1, 15.), rng.uniform(.001, .1)
            maximum = rng.uniform(.2, .9)
            damage = rng.uniform(0., maximum)
            next_damage = evolve(damage, original, threshold, rate, dt, maximum)
            self.assertGreaterEqual(next_damage, damage)
            self.assertLessEqual(next_damage, maximum)
            if original <= threshold:
                self.assertEqual(next_damage, damage)
            # Increasing damage must not increase the stiffness of either
            # isotropic FEM or reinforcing fiber XPBD rows.
            alpha = rng.uniform(.000001, .1)
            self.assertGreaterEqual(alpha / (1-next_damage),
                                    alpha / (1-damage) - 1e-12)

    def test_constant_strain_rate_independence_and_irreversibility(self):
        for rate in (.1, 1., 5., 25.):
            for step_count in (2, 10, 100, 1000):
                single = evolve(0., .6, .2, rate, 1., .8)
                split = 0.
                for _ in range(step_count):
                    split = evolve(split, .6, .2, rate, 1./step_count, .8)
                self.assertAlmostEqual(single, split, delta=1e-12)
        damaged = evolve(0., 1.0, .1, 5., .1, .8)
        self.assertGreater(damaged, 0.)
        self.assertEqual(evolve(damaged, 0., .1, 5., .1, .8), damaged)

    def test_rigid_motion_and_inverted_elements(self):
        identity = [[1., 0., 0.], [0., 1., 0.], [0., 0., 1.]]
        self.assertAlmostEqual(strain_from_f(identity), 0.)
        theta = 1.23
        cs, sn = math.cos(theta), math.sin(theta)
        rotation = [[cs, -sn, 0.], [sn, cs, 0.], [0., 0., 1.]]
        self.assertAlmostEqual(strain_from_f(rotation), 0., delta=1e-15)
        inverted = [[-1., 0., 0.], [0., 1., 0.], [0., 0., 1.]]
        self.assertIsNone(strain_from_f(inverted))
        self.assertIsNone(strain_from_f([[0.,0.,0.],[0.,1.,0.],[0.,0.,1.]]))

    def test_default_off_history_reuse_and_engine_wiring(self):
        server = (ROOT/"servers/physics_3d/physics_server_3d.cpp").read_text()
        space_h = (ROOT/"modules/godot_physics_3d/godot_space_3d.h").read_text()
        space_cpp = (ROOT/"modules/godot_physics_3d/godot_space_3d.cpp").read_text()
        body_h = (ROOT/"modules/godot_physics_3d/godot_soft_body_3d.h").read_text()
        body = (ROOT/"modules/godot_physics_3d/godot_soft_body_3d.cpp").read_text()
        helper = (ROOT/"servers/physics_fem_tetra_damage.h").read_text()
        self.assertIn('soft_body_tetra_damage_rate", PROPERTY_HINT_RANGE', server)
        self.assertIn('soft_body_tetra_damage_rate = 0.0;', space_h)
        self.assertIn('soft_body_tetra_damage_rate = Math::is_finite(', space_cpp)
        self.assertIn('LocalVector<real_t> xpbd_fem_tetra_damage;', body_h)
        self.assertIn('damage_rate > real_t(0.0)', body)
        self.assertIn('xpbd_fem_tetra_damage.resize(', body)
        self.assertIn('xpbd_fem_tetra_damage.reset();', body)
        self.assertIn('physics_fem_tetra_damage_strain(', body)
        self.assertIn('physics_fem_tetra_accumulate_damage(', body)
        self.assertIn('physics_fem_tetra_damage_alpha(fem_alpha', body)
        self.assertIn('physics_fem_tetra_damage_alpha(fem_fiber_alpha', body)
        self.assertIn('1.0 - Math::exp(-p_rate * p_delta * intensity)', helper)
        self.assertIn('det > 1e-9', helper)
        self.assertLess(body.index('physics_fem_tetra_accumulate_damage('),
                        body.index('for (int isolve = 0; isolve < iteration_count; ++isolve)'))


if __name__ == "__main__":
    unittest.main()
