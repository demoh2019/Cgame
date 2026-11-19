"""Tetrahedral FEM objective viscoelasticity: numeric reference and wiring.

The six velocity constraints use dE/dt, where E is Green-Lagrange strain.
The random reference tests momentum, angular momentum and kinetic-energy
dissipation; C++ engine compilation is a separate validation requirement.
"""
import math
from pathlib import Path
import random
import unittest

ROOT = Path(__file__).resolve().parents[2]


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1],
            a[2] * b[0] - a[0] * b[2],
            a[0] * b[1] - a[1] * b[0])


def add(a, b):
    return tuple(x + y for x, y in zip(a, b))


def sub(a, b):
    return tuple(x - y for x, y in zip(a, b))


def scale(a, s):
    return tuple(x * s for x in a)


def mag(a):
    return math.sqrt(dot(a, a))


def reference_damping(points, velocities, inv_masses, fraction):
    # Independent reference: rest tetra is the positive unit basis, so
    # F columns are the three deformed edges from its first vertex.
    f = [sub(points[j+1], points[0]) for j in range(3)]
    determinant = dot(f[0], cross(f[1], f[2]))
    if determinant <= 1e-9:
        return None
    coeff = ((-1., -1., -1.), (1., 0., 0.), (0., 1., 0.), (0., 0., 1.))
    values = [list(v) for v in velocities]
    changed = False
    for i, j in ((0, 0), (1, 1), (2, 2), (0, 1), (0, 2), (1, 2)):
        grads = [
            tuple(.5 * (coeff[k][j] * f[i][axis] +
                          coeff[k][i] * f[j][axis])
                  for axis in range(3))
            for k in range(4)
        ]
        m = sum(inv_masses[k] * dot(grads[k], grads[k]) for k in range(4))
        rate = sum(dot(grads[k], sub(values[k], values[0]))
                   for k in range(1, 4))
        if m <= 0 or rate == 0:
            continue
        delta = -fraction * rate / m
        for k in range(4):
            values[k] = list(add(values[k], scale(grads[k], inv_masses[k] * delta)))
        changed = True
    return tuple(tuple(v) for v in values), changed


def momentum(values, inv):
    return tuple(sum(values[i][axis] / inv[i] for i in range(4)) for axis in range(3))


def angular_momentum(points, values, inv):
    result = (0., 0., 0.)
    for i in range(4):
        result = add(result, scale(cross(points[i], values[i]), 1. / inv[i]))
    return result


def energy(values, inv):
    return sum(dot(v, v) / (2 * mass) for v, mass in zip(values, inv) if mass > 0)


class TetraViscosityContracts(unittest.TestCase):
    def test_5000_randomized_momentum_energy_and_rigid_modes(self):
        rng = random.Random(0xF3E20BAD)
        for case in range(5000):
            points = ((0., 0., 0.),
                      (rng.uniform(.6, 1.4), rng.uniform(-.1, .1), rng.uniform(-.1, .1)),
                      (rng.uniform(-.1, .1), rng.uniform(.6, 1.4), rng.uniform(-.1, .1)),
                      (rng.uniform(-.1, .1), rng.uniform(-.1, .1), rng.uniform(.6, 1.4)))
            inv = tuple(rng.uniform(.2, 3.) for _ in range(4))
            if case % 5 == 0:
                linear = tuple(rng.uniform(-4., 4.) for _ in range(3))
                omega = tuple(rng.uniform(-2., 2.) for _ in range(3))
                velocities = tuple(add(linear, cross(omega, p)) for p in points)
            else:
                velocities = tuple(tuple(rng.uniform(-5., 5.) for _ in range(3))
                                   for _ in range(4))
            fraction = rng.uniform(.01, 1.)
            result = reference_damping(points, velocities, inv, fraction)
            self.assertIsNotNone(result)
            after, _ = result
            self.assertLessEqual(energy(after, inv), energy(velocities, inv) + 1e-9)
            self.assertLessEqual(mag(sub(momentum(after, inv),
                                         momentum(velocities, inv))), 1e-9)
            self.assertLessEqual(mag(sub(angular_momentum(points, after, inv),
                                         angular_momentum(points, velocities, inv))), 1e-9)
            if case % 5 == 0:
                for before_v, after_v in zip(velocities, after):
                    self.assertLess(mag(sub(after_v, before_v)), 1e-9)

    def test_pinned_vertices_and_fraction_limits(self):
        p = ((0., 0., 0.), (1., 0., 0.), (0., 1., 0.), (0., 0., 1.))
        v = ((0., 0., 0.), (3., 0., 0.), (0., 0., 0.), (0., 0., 0.))
        inv = (0., 1., 1., 1.)
        result = reference_damping(p, v, inv, 1.)
        self.assertIsNotNone(result)
        self.assertEqual(result[0][0], v[0])
        self.assertLess(energy(result[0], inv), energy(v, inv))
        self.assertIsNone(reference_damping(
            (p[0], p[1], p[2], (0., 0., -1.)), v, inv, 1.))

    def test_disabled_setting_and_engine_order(self):
        server = (ROOT / "servers/physics_3d/physics_server_3d.cpp").read_text()
        space_h = (ROOT / "modules/godot_physics_3d/godot_space_3d.h").read_text()
        space_cpp = (ROOT / "modules/godot_physics_3d/godot_space_3d.cpp").read_text()
        soft = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.cpp").read_text()
        helper = (ROOT / "servers/physics_fem_tetra_viscosity.h").read_text()
        self.assertIn('soft_body_tetra_fem_damping_rate", PROPERTY_HINT_RANGE', server)
        self.assertIn('soft_body_tetra_fem_damping_rate = 0.0;', space_h)
        self.assertIn('soft_body_tetra_fem_damping_rate = Math::is_finite(', space_cpp)
        self.assertIn('get_soft_body_tetra_fem_damping_rate()', soft)
        self.assertIn('get_soft_body_tetra_fem_compliance() > real_t(0.0)', soft)
        self.assertIn('physics_fem_tetra_damp_strain_rate(', soft)
        self.assertIn('1.0 - Math::exp(-double(fem_damping_rate) * double(p_delta))', soft)
        self.assertLess(soft.index('physics_fem_tetra_damp_strain_rate('),
                        soft.index('// Solve velocities.'))
        self.assertIn('const int modes[6][2]', helper)
        self.assertIn('coeff[vertex][j] * deformation[axis][i]', helper)
        self.assertIn('final_energy > initial_energy', helper)
        self.assertIn('r_va = next[0];', helper)


if __name__ == "__main__":
    unittest.main()
