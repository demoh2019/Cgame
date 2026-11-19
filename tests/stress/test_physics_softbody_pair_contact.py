"""Deterministic reference contracts for the two-way SoftBody3D pair stage.

This is not a substitute for engine-level C++ tests: it checks XPBD
momentum, pinned vertices and source wiring without a native build.
"""

import math
from pathlib import Path
import random
import unittest


ROOT = Path(__file__).resolve().parents[2]


def add(a, b):
    return tuple(x + y for x, y in zip(a, b))


def mul(a, s):
    return tuple(x * s for x in a)


def delta(a, b):
    return tuple(x - y for x, y in zip(a, b))


def mass_momentum(positions, inverse_masses):
    total = [0.0, 0.0, 0.0]
    for point, inv_mass in zip(positions, inverse_masses):
        if inv_mass == 0:
            continue
        for axis in range(3):
            total[axis] += point[axis] / inv_mass
    return total


def solve_planar_contact(positions, velocities, inverse_masses, bary, thickness, dt, compliance):
    point, a, b, c = positions
    assert abs(a[2] - b[2]) < 1e-10 and abs(a[2] - c[2]) < 1e-10
    sign = 1 if point[2] >= a[2] else -1
    penetration = thickness - sign * (point[2] - a[2])
    if penetration <= 0:
        return positions, velocities, 0.0
    alpha = compliance / (dt * dt)
    inv_effective_mass = inverse_masses[0] + sum(
        inverse_masses[i + 1] * bary[i] ** 2 for i in range(3)
    )
    if inv_effective_mass == 0:
        return positions, velocities, 0.0
    impulse = penetration / (inv_effective_mass + alpha)
    changes = [
        (0., 0., sign * inverse_masses[0] * impulse),
        *[(0., 0., -sign * bary[i] * inverse_masses[i + 1] * impulse) for i in range(3)]
    ]
    corrected = tuple(add(x, dx) for x, dx in zip(positions, changes))
    next_velocities = tuple(add(v, mul(dx, 1. / dt))
                            for v, dx in zip(velocities, changes))
    return corrected, next_velocities, impulse


class TestSoftSoftContact(unittest.TestCase):
    def test_randomized_two_way_position_and_momentum(self):
        rng = random.Random(0x531AEC)
        for _ in range(2000):
            u, v = rng.random(), rng.random()
            if u + v > 1.:
                u, v = 1. - u, 1. - v
            bary = (1. - u - v, u, v)
            scale = rng.uniform(0.25, 5.)
            a, b, c = (0., 0., 0.), (scale, 0., 0.), (0., scale, 0.)
            thickness = rng.uniform(0.01, 0.1)
            z = rng.uniform(-0.95 * thickness, 0.95 * thickness)
            point = (u * scale, v * scale, z)
            positions = (point, a, b, c)
            velocities = ((0., 0., 0.),) * 4
            inverse_masses = tuple(rng.uniform(0.1, 5.) for _ in range(4))
            old_momentum = mass_momentum(positions, inverse_masses)
            corrected, next_velocities, impulse = solve_planar_contact(
                positions, velocities, inverse_masses, bary, thickness, 1. / 60., 0.0)
            self.assertGreater(impulse, 0.)
            after_momentum = mass_momentum(corrected, inverse_masses)
            for old, new in zip(old_momentum, after_momentum):
                self.assertAlmostEqual(old, new, delta=1e-9)
            self.assertGreater(abs(corrected[0][2] - z), 0.)
            for index in range(4):
                self.assertAlmostEqual(next_velocities[index][2],
                                       (corrected[index][2] - positions[index][2]) * 60.,
                                       delta=1e-9)

    def test_pins_and_no_adhesion(self):
        positions = ((.2, .3, .01), (0., 0., 0.), (1., 0., 0.), (0., 1., 0.))
        zero = ((0., 0., 0.),) * 4
        bary = (.5, .2, .3)
        moved, velocities, impulse = solve_planar_contact(
            positions, zero, (1., 0., 0., 0.), bary, .1, .02, 0.)
        self.assertGreater(impulse, 0.)
        self.assertEqual(moved[1:], positions[1:])
        self.assertEqual(velocities[1:], zero[1:])
        untouched, _, impulse = solve_planar_contact(
            ((.2, .3, .2), *positions[1:]), zero,
            (1., 1., 1., 1.), bary, .1, .02, 0.)
        self.assertEqual(impulse, 0.)
        self.assertEqual(untouched[0][2], .2)

    def test_wiring_budget_exception_and_default(self):
        space_h = (ROOT / "modules/godot_physics_3d/godot_space_3d.h").read_text()
        space_cpp = (ROOT / "modules/godot_physics_3d/godot_space_3d.cpp").read_text()
        soft_cpp = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.cpp").read_text()
        step = (ROOT / "modules/godot_physics_3d/godot_step_3d.cpp").read_text()
        settings = (ROOT / "servers/physics_3d/physics_server_3d.cpp").read_text()
        header = (ROOT / "servers/physics_softbody_pair_contact.h").read_text()
        self.assertIn('soft_body_pair_collision_thickness", PROPERTY_HINT_RANGE', settings)
        self.assertIn('soft_body_pair_collision_thickness = 0.0;', space_h)
        self.assertIn('soft_body_pair_collision_thickness = Math::is_finite(', space_cpp)
        self.assertIn('physics_xpbd_solve_self_collision(', header)
        self.assertIn('bool GodotSoftBody3D::solve_pair_contacts(', soft_cpp)
        self.assertIn('face_tree.aabb_query(', soft_cpp)
        self.assertIn('max_contacts = MIN(p_max_contacts, uint32_t(2048))', soft_cpp)
        self.assertIn('a->interacts_with(b)', step)
        self.assertIn('a->has_exception(b->get_self())', step)
        self.assertIn('max_pair_checks = 16384', step)
        self.assertIn('a->solve_pair_contacts(*b, p_delta', step)
        self.assertLess(step.index('sb->self()->solve_constraints(p_delta);'),
                        step.index('a->solve_pair_contacts(*b, p_delta'))


if __name__ == "__main__":
    unittest.main()
