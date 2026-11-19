"""Randomized physical and source-wiring checks for opt-in SoftBody pair friction.

This checks the mass-weighted Coulomb velocity impulse against conservation,
kinetic energy and normal-velocity invariants. C++ engine compilation and
scene-level regression tests remain separate validation requirements.
"""
import math
from pathlib import Path
import random
import unittest

ROOT = Path(__file__).resolve().parents[2]


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def add(a, b):
    return tuple(x + y for x, y in zip(a, b))


def sub(a, b):
    return tuple(x - y for x, y in zip(a, b))


def mul(a, s):
    return tuple(x * s for x in a)


def norm(a):
    return math.sqrt(dot(a, a))


def friction(velocities, inv_masses, bary, normal, mu, contact_lambda, dt):
    weights = (1.0, *bary)
    relative = velocities[0]
    for w, v in zip(weights[1:], velocities[1:]):
        relative = sub(relative, mul(v, w))
    tangent = sub(relative, mul(normal, dot(normal, relative)))
    tangent_speed = norm(tangent)
    effective_inverse_mass = sum(w * w * inv for w, inv in zip(weights, inv_masses))
    if mu <= 0 or contact_lambda <= 0 or tangent_speed <= 0 or effective_inverse_mass <= 0:
        return velocities, 0.0
    budget = mu * contact_lambda / dt
    impulse_scale = min(1 / effective_inverse_mass, budget / tangent_speed)
    impulse = mul(tangent, -impulse_scale)
    after = tuple(add(v, mul(impulse, inv * (1 if i == 0 else -weights[i])))
                  for i, (v, inv) in enumerate(zip(velocities, inv_masses)))
    return after, norm(impulse)


def momentum(velocities, inv_masses):
    result = (0.0, 0.0, 0.0)
    for v, inv in zip(velocities, inv_masses):
        if inv:
            result = add(result, mul(v, 1 / inv))
    return result


def energy(velocities, inv_masses):
    return sum(dot(v, v) / (2 * inv) for v, inv in zip(velocities, inv_masses) if inv)


def relative_tangent(velocities, bary, normal):
    rel = velocities[0]
    for w, v in zip(bary, velocities[1:]):
        rel = sub(rel, mul(v, w))
    return sub(rel, mul(normal, dot(rel, normal))), dot(rel, normal)


class TestSoftBodyPairFriction(unittest.TestCase):
    def test_3000_randomized_invariants(self):
        rng = random.Random(0xC71F1A)
        for _ in range(3000):
            weights = [rng.uniform(0.01, 1) for _ in range(3)]
            total = sum(weights)
            bary = tuple(w / total for w in weights)
            n = [rng.uniform(-1, 1) for _ in range(3)]
            n = mul(n, 1 / norm(n))
            inv = tuple(rng.uniform(.1, 3) for _ in range(4))
            velocities = tuple(tuple(rng.uniform(-4, 4) for _ in range(3)) for _ in range(4))
            mu, contact_lambda, dt = rng.uniform(.01, 3), rng.uniform(.001, .2), rng.uniform(.001, .1)
            before_t, before_n = relative_tangent(velocities, bary, n)
            after, impulse = friction(velocities, inv, bary, n, mu, contact_lambda, dt)
            after_t, after_n = relative_tangent(after, bary, n)
            self.assertLessEqual(impulse, mu * contact_lambda / dt + 1e-9)
            self.assertLessEqual(norm(after_t), norm(before_t) + 1e-9)
            self.assertAlmostEqual(after_n, before_n, delta=1e-9)
            self.assertLessEqual(energy(after, inv), energy(velocities, inv) + 1e-9)
            for old, new in zip(momentum(velocities, inv), momentum(after, inv)):
                self.assertAlmostEqual(old, new, delta=1e-9)

    def test_pinned_face_and_no_slip(self):
        original = ((4., 2., 0.), (0., 0., 0.), (0., 0., 0.), (0., 0., 0.))
        final, _ = friction(original, (1., 0., 0., 0.), (.5, .2, .3),
                            (0., 0., 1.), 2., 1., .02)
        self.assertEqual(final[0], (0., 0., 0.))
        self.assertEqual(final[1:], original[1:])
        all_equal = ((1., 2., 3.),) * 4
        self.assertEqual(friction(all_equal, (1., 1., 1., 1.), (.5, .2, .3),
                                  (0., 0., 1.), 2., 1., .02)[0], all_equal)

    def test_source_wiring_and_disabled_default(self):
        server = (ROOT / "servers/physics_3d/physics_server_3d.cpp").read_text()
        space_h = (ROOT / "modules/godot_physics_3d/godot_space_3d.h").read_text()
        space_cpp = (ROOT / "modules/godot_physics_3d/godot_space_3d.cpp").read_text()
        step = (ROOT / "modules/godot_physics_3d/godot_step_3d.cpp").read_text()
        soft_cpp = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.cpp").read_text()
        contact = (ROOT / "servers/physics_softbody_pair_contact.h").read_text()
        self.assertIn('soft_body_pair_collision_friction", PROPERTY_HINT_RANGE', server)
        self.assertIn('soft_body_pair_collision_friction = 0.0;', space_h)
        self.assertIn('soft_body_pair_collision_friction = Math::is_finite(', space_cpp)
        self.assertIn('get_soft_body_pair_collision_friction()', step)
        self.assertIn('pair_compliance, pair_friction, max_contacts', step)
        self.assertIn('physics_softbody_solve_pair_friction(', soft_cpp)
        self.assertIn('p_friction > real_t(0.0)', soft_cpp)
        self.assertIn('double(p_mu) * double(p_normal_lambda) / double(p_delta)', contact)
        self.assertLess(soft_cpp.index('physics_softbody_solve_pair_vertex_face('),
                        soft_cpp.index('physics_softbody_solve_pair_friction('))
        self.assertLess(soft_cpp.index('physics_softbody_solve_pair_friction('),
                        soft_cpp.index('p_body.update_normals_and_centroids();'))


if __name__ == "__main__":
    unittest.main()
