"""Closed-mesh bulk viscosity numerical and Cgame integration contracts."""

import math
import pathlib
import random
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
P = ((0., 0., 0.), (1., 0., 0.), (0., 1., 0.), (0., 0., 1.))
G = ((-1/6, -1/6, -1/6), (1/6, 0, 0), (0, 1/6, 0), (0, 0, 1/6))


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def cross(a, b):
    return (a[1]*b[2]-a[2]*b[1],
            a[2]*b[0]-a[0]*b[2],
            a[0]*b[1]-a[1]*b[0])


def project(velocities, inverse_masses, fraction):
    k = sum(w*dot(g, g) for w, g in zip(inverse_masses, G))
    rate = sum(dot(g, v) for w, g, v in zip(inverse_masses, G, velocities) if w > 0)
    if not k > 0 or not fraction > 0:
        return velocities
    impulse = -fraction * rate / k
    return [tuple(v[j]+w*g[j]*impulse for j in range(3))
            for v, g, w in zip(velocities, G, inverse_masses)]


def energy(velocities, inverse_masses):
    return sum(dot(v, v)/(2*w) for v, w in zip(velocities, inverse_masses) if w > 0)


class TestBulkViscosity(unittest.TestCase):
    def test_30000_mass_weighted_random_cases(self):
        rng = random.Random(0xBB115)
        count = 0
        for _ in range(30000):
            v = [tuple(rng.uniform(-20, 20) for j in range(3)) for i in range(4)]
            w = [0 if rng.random() < .12 else 10 ** rng.uniform(-2, 2) for i in range(4)]
            k = sum(wi*dot(g, g) for wi, g in zip(w, G))
            if k == 0:
                continue
            fraction = rng.random()
            nxt = project(v, w, fraction)
            d0 = sum(dot(g, vi) for wi, g, vi in zip(w, G, v) if wi > 0)
            d1 = sum(dot(g, vi) for wi, g, vi in zip(w, G, nxt) if wi > 0)
            self.assertAlmostEqual(d1, (1-fraction)*d0, delta=1e-7)
            self.assertLessEqual(energy(nxt, w), energy(v, w) + 1e-7)
            for i, wi in enumerate(w):
                if not wi:
                    self.assertEqual(nxt[i], v[i])
            count += 1
        self.assertGreater(count, 29000)

    def test_conservation_of_linear_and_angular_momentum(self):
        rng = random.Random(0xCC01)
        for _ in range(2000):
            v = [tuple(rng.uniform(-5, 5) for j in range(3)) for i in range(4)]
            nxt = project(v, [1]*4, 0.85)
            delta = [tuple(n[j]-o[j] for j in range(3)) for n, o in zip(nxt, v)]
            linear = [sum(q[j] for q in delta) for j in range(3)]
            torques = [cross(p, q) for p, q in zip(P, delta)]
            angular = [sum(q[j] for q in torques) for j in range(3)]
            self.assertTrue(all(abs(q)<1e-12 for q in linear+angular))

    def test_rigid_motion_and_exponential_time_subdivision(self):
        translation = (3, -5, 2)
        omega = (4, 7, -1)
        v = [tuple(translation[j]+cross(omega, p)[j] for j in range(3)) for p in P]
        nxt = project(v, [1]*4, 0.9)
        for a, b in zip(v, nxt):
            for ai, bi in zip(a, b):
                self.assertAlmostEqual(ai, bi, delta=1e-12)
        init = [(0, 0, 0), (1, 0, 0), (0, 1, 0), (0, 0, 1)]
        full = 1-math.exp(-3*.2)
        half = 1-math.exp(-3*.1)
        once = project(init, [1]*4, full)
        twice = project(project(init, [1]*4, half), [1]*4, half)
        for va, vb in zip(once, twice):
            for a, b in zip(va, vb):
                self.assertAlmostEqual(a, b, delta=1e-12)

    def test_engine_source_wiring(self):
        soft = (ROOT/"modules/godot_physics_3d/godot_soft_body_3d.cpp").read_text()
        sh = (ROOT/"modules/godot_physics_3d/godot_soft_body_3d.h").read_text()
        space = (ROOT/"modules/godot_physics_3d/godot_space_3d.cpp").read_text()
        space_h = (ROOT/"modules/godot_physics_3d/godot_space_3d.h").read_text()
        server = (ROOT/"servers/physics_3d/physics_server_3d.cpp").read_text()
        helper = (ROOT/"servers/physics_softbody_volume_damping.h").read_text()
        self.assertIn("void GodotSoftBody3D::damp_volume_rate(double p_fraction)", soft)
        self.assertIn("physics_softbody_volume_face_gradients(", soft)
        self.assertIn("physics_softbody_bulk_viscosity_impulse(", soft)
        self.assertIn("physics_softbody_bulk_viscosity_velocity(", soft)
        self.assertIn("void damp_volume_rate(double p_fraction);", sh)
        self.assertIn("get_soft_body_volume_damping_rate() <= 0.0", soft)
        self.assertIn("volume_damping_rate > real_t(0.0) && p_delta > real_t(0.0)", soft)
        self.assertLess(soft.index("damp_volume_rate(fraction);"), soft.index("// Solve velocities."))
        self.assertIn('GLOBAL_GET("physics/3d/solver/soft_body_volume_damping_rate")', space)
        self.assertIn("real_t soft_body_volume_damping_rate = 0.0;", space_h)
        self.assertIn('"physics/3d/solver/soft_body_volume_damping_rate"', server)
        self.assertIn("p_inverse_mass_gradient > 0.0", helper)


if __name__ == "__main__":
    unittest.main()
