"""Reference-level contracts for Cgame's optional XPBD hinge angular damping.

Uses no engine runtime or third-party Python packages. The C++ tests exercise
the actual solver; these checks add randomized physical-invariant coverage.
"""

import math
import pathlib
import random
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
POS = ((-1., 0., 0.), (1., 0., 0.), (0., 1., 0.), (0., 0., 1.))


def add(a, b):
    return tuple(x + y for x, y in zip(a, b))


def sub(a, b):
    return tuple(x - y for x, y in zip(a, b))


def mul(a, s):
    return tuple(x * s for x in a)


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1],
            a[2] * b[0] - a[0] * b[2],
            a[0] * b[1] - a[1] * b[0])


def jacobian(p):
    a, b, c, d = p
    edge = sub(b, a)
    normal_c = cross(edge, sub(c, a))
    normal_d = cross(sub(d, a), edge)
    edge_sq = dot(edge, edge)
    nc_sq = dot(normal_c, normal_c)
    nd_sq = dot(normal_d, normal_d)
    if min(edge_sq, nc_sq, nd_sq) <= 1e-10:
        return None
    grad_c = mul(normal_c, -math.sqrt(edge_sq) / nc_sq)
    grad_d = mul(normal_d, -math.sqrt(edge_sq) / nd_sq)
    grad_a = add(mul(grad_c, dot(sub(c, b), edge) / edge_sq),
                 mul(grad_d, dot(sub(d, b), edge) / edge_sq))
    grad_b = add(mul(grad_c, dot(sub(a, c), edge) / edge_sq),
                 mul(grad_d, dot(sub(a, d), edge) / edge_sq))
    return (grad_a, grad_b, grad_c, grad_d)


def signed_dihedral(p):
    a, b, c, d = p
    edge = sub(b, a)
    n0 = cross(edge, sub(c, a))
    n1 = cross(sub(d, a), edge)
    length = lambda x: math.sqrt(dot(x, x))
    e = mul(edge, 1. / length(edge))
    n0 = mul(n0, 1. / length(n0))
    n1 = mul(n1, 1. / length(n1))
    return math.atan2(dot(e, cross(n0, n1)), dot(n0, n1))


def damp(p, velocities, inverse_masses, fraction):
    gradients = jacobian(p)
    if gradients is None:
        return None
    effective = sum(w * dot(g, g) for w, g in zip(inverse_masses, gradients))
    if effective <= 0:
        return None
    relative_rate = sum(dot(g, v) for g, v in zip(gradients, velocities))
    impulse = -fraction * relative_rate / effective
    return tuple(add(v, mul(g, w * impulse))
                 for v, g, w in zip(velocities, gradients, inverse_masses))


def kinetic_energy(v, inv):
    return sum(dot(x, x) / (2 * w) for x, w in zip(v, inv))


def momentum(v, inv):
    out = (0., 0., 0.)
    for velocity, w in zip(v, inv):
        out = add(out, mul(velocity, 1. / w))
    return out


class TestDihedralDamping(unittest.TestCase):
    def test_randomized_conservation_and_dissipation(self):
        rng = random.Random(0xC6A9E)
        for _ in range(2000):
            pos = tuple(tuple(rng.uniform(-2, 2) for _ in range(3)) for _ in range(4))
            gradients = jacobian(pos)
            if gradients is None:
                continue
            velocities = tuple(tuple(rng.uniform(-5, 5) for _ in range(3))
                               for _ in range(4))
            inv = tuple(rng.uniform(0.2, 3.0) for _ in range(4))
            fraction = rng.random()
            after = damp(pos, velocities, inv, fraction)
            self.assertIsNotNone(after)
            before_rate = sum(dot(g, v) for g, v in zip(gradients, velocities))
            after_rate = sum(dot(g, v) for g, v in zip(gradients, after))
            self.assertAlmostEqual(after_rate, (1. - fraction) * before_rate,
                                   delta=1e-9 * (1 + abs(before_rate)))
            self.assertLessEqual(kinetic_energy(after, inv),
                                 kinetic_energy(velocities, inv) + 1e-9)
            for before_p, after_p in zip(momentum(velocities, inv), momentum(after, inv)):
                self.assertAlmostEqual(before_p, after_p, delta=1e-9)

    def test_rigid_motion_and_pins(self):
        omega = (0.2, -0.1, 0.7)
        translation = (1., 2., -3.)
        velocities = tuple(add(cross(omega, p), translation) for p in POS)
        after = damp(POS, velocities, (1., 1., 1., 1.), 1.)
        for before_v, after_v in zip(velocities, after):
            for before_c, after_c in zip(before_v, after_v):
                self.assertAlmostEqual(before_c, after_c, delta=1e-12)
        pinned = damp(POS, ((0., 0., 0.),) * 3 + ((0., 4., 0.),),
                      (0., 0., 0., 1.), 1.)
        self.assertEqual(pinned[:3], ((0., 0., 0.),) * 3)
        self.assertAlmostEqual(pinned[3][1], 0., delta=1e-12)

    def test_angular_jacobian_matches_finite_difference(self):
        rng = random.Random(1203)
        for _ in range(120):
            pos = tuple(add(p, tuple(rng.uniform(-0.15, 0.15) for _ in range(3)))
                        for p in POS)
            velocities = tuple(tuple(rng.uniform(-2, 2) for _ in range(3))
                               for _ in range(4))
            grads = jacobian(pos)
            expected = sum(dot(g, v) for g, v in zip(grads, velocities))
            h = 1e-6
            nxt = tuple(add(p, mul(v, h)) for p, v in zip(pos, velocities))
            delta = signed_dihedral(nxt) - signed_dihedral(pos)
            rate = math.atan2(math.sin(delta), math.cos(delta)) / h
            self.assertAlmostEqual(rate, expected, delta=2e-4)

    def test_wiring_and_disabled_default(self):
        server = (ROOT / "servers/physics_3d/physics_server_3d.cpp").read_text()
        header = (ROOT / "modules/godot_physics_3d/godot_space_3d.h").read_text()
        space = (ROOT / "modules/godot_physics_3d/godot_space_3d.cpp").read_text()
        solver = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.cpp").read_text()
        self.assertIn('soft_body_dihedral_damping", PROPERTY_HINT_RANGE', server)
        self.assertIn('suffix:1/s"), 0.0)', server)
        self.assertIn('real_t soft_body_dihedral_damping = 0.0;', header)
        self.assertIn('soft_body_dihedral_damping = Math::is_finite(', space)
        self.assertIn('physics_softbody_damp_dihedral(', solver)
        self.assertIn('!xpbd_dihedral_hinges.is_empty()', solver)
        self.assertLess(solver.index('physics_softbody_damp_dihedral('),
                        solver.index('node.x = node.q + node.v * p_delta;'))


if __name__ == "__main__":
    unittest.main()
