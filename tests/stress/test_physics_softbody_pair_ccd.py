"""Reference contracts for opt-in inter-body SoftBody3D swept vertex/face CCD.

The native code uses a cubic plane determinant for deforming triangles.
This independent planar reference checks moving faces/vertices, TOI,
inverse-mass corrections, bounding-box conservativeness and source wiring.
"""
import math
from pathlib import Path
import random
import unittest

ROOT = Path(__file__).resolve().parents[2]


def linear_crossing(start_relative, end_relative):
    if start_relative == 0 or start_relative * end_relative >= 0:
        return None
    t = -start_relative / (end_relative - start_relative)
    return t if 0.0 < t < 1.0 else None


def swept_normal_contact(vertex_z, face_z, bary, inverse_masses,
                         previous_sign, thickness, dt):
    signed_normal = 1 if previous_sign > 0 else -1
    signed_separation = signed_normal * (vertex_z - face_z)
    weights = (1.0, *bary)
    inverse_effective_mass = sum(
        inv * weight * weight
        for inv, weight in zip(inverse_masses, weights)
    )
    if inverse_effective_mass == 0:
        return None
    impulse = max(0., (thickness - signed_separation) / inverse_effective_mass)
    deltas = (
        signed_normal * inverse_masses[0] * impulse,
        *[-signed_normal * inverse_masses[i+1] * bary[i] * impulse for i in range(3)]
    )
    return deltas, tuple(dz/dt for dz in deltas), impulse


class TestSoftPairCCD(unittest.TestCase):
    def test_3000_randomized_crossings_and_momentum(self):
        rng = random.Random(0xC0DD)
        max_error = 0.
        for _ in range(3000):
            u, v = rng.random(), rng.random()
            if u + v > 1.:
                u, v = 1.-u, 1.-v
            bary = (1.-u-v, u, v)
            start_face, end_face = rng.uniform(-2, 2), rng.uniform(-2, 2)
            start_relative = rng.choice((-1., 1.)) * rng.uniform(.01, 3.)
            end_relative = -start_relative * rng.uniform(.05, 3.)
            start_vertex = start_face + start_relative
            end_vertex = end_face + end_relative
            toi = linear_crossing(start_vertex-start_face, end_vertex-end_face)
            self.assertIsNotNone(toi)
            self.assertGreater(toi, 0.)
            self.assertLess(toi, 1.)
            # Both the moving face and the point coincide at the impact time.
            impact_vertex = start_vertex + (end_vertex-start_vertex)*toi
            impact_face = start_face + (end_face-start_face)*toi
            self.assertAlmostEqual(impact_vertex, impact_face, delta=1e-12)
            # Their swept AABBs necessarily overlap on the crossing axis.
            self.assertLessEqual(max(min(start_face, end_face),
                                     min(start_vertex, end_vertex)),
                                 min(max(start_face, end_face),
                                     max(start_vertex, end_vertex)) + 1e-12)
            inverse_masses = tuple(rng.choice((0., rng.uniform(.1, 4.)))
                                   for _ in range(4))
            if all(x == 0. for x in inverse_masses):
                continue
            dt = rng.uniform(.001, .08)
            thickness = rng.uniform(.001, .1)
            result = swept_normal_contact(end_vertex, end_face, bary,
                                          inverse_masses, start_relative,
                                          thickness, dt)
            self.assertIsNotNone(result)
            displacements, velocities, impulse = result
            self.assertGreaterEqual(impulse, 0.)
            signed_normal = 1 if start_relative > 0 else -1
            face_correction = sum(bary[i] * displacements[i+1] for i in range(3))
            remaining = signed_normal * ((end_vertex+displacements[0]) -
                                         (end_face+face_correction))
            self.assertGreaterEqual(remaining, thickness - 1e-9)
            # Pins introduce EXTERNAL reaction impulses. Linear momentum is
            # conserved by the four free particles only if all four move.
            # The zero-inverse-mass cases are checked for exact pinning below.
            if all(inv_mass > 0. for inv_mass in inverse_masses):
                momentum_delta = sum(displacements[i] / inverse_masses[i]
                                     for i in range(4))
                max_error = max(max_error, abs(momentum_delta))
                self.assertAlmostEqual(momentum_delta, 0., delta=1e-9)
            for index, inv_mass in enumerate(inverse_masses):
                self.assertAlmostEqual(velocities[index] * dt,
                                       displacements[index], delta=1e-9)
                if inv_mass == 0.:
                    self.assertEqual(displacements[index], 0.)
        self.assertLess(max_error, 1e-9)

    def test_vertex_and_moving_face_and_no_crossing(self):
        self.assertAlmostEqual(linear_crossing(1., -1.), .5)
        self.assertAlmostEqual(linear_crossing(-1., 1.), .5)
        self.assertIsNone(linear_crossing(1., .1))
        self.assertIsNone(linear_crossing(0., -1.))
        self.assertIsNone(linear_crossing(-1., -1.))

        pinned_face = swept_normal_contact(
            -1., 0., (.5, .2, .3), (1., 0., 0., 0.), 1.,
            .05, .02)
        self.assertAlmostEqual(-1. + pinned_face[0][0], .05)
        self.assertEqual(pinned_face[0][1:], (0., 0., 0.))

        pinned_vertex = swept_normal_contact(
            0., -1., (.5, .2, .3), (0., 1., 1., 1.), -1.,
            .05, .02)
        self.assertEqual(pinned_vertex[0][0], 0.)
        self.assertTrue(all(x > 0. for x in pinned_vertex[0][1:]))

    def test_opt_in_history_and_bvh_wiring(self):
        soft_h = (ROOT/"modules/godot_physics_3d/godot_soft_body_3d.h").read_text()
        soft = (ROOT/"modules/godot_physics_3d/godot_soft_body_3d.cpp").read_text()
        step = (ROOT/"modules/godot_physics_3d/godot_step_3d.cpp").read_text()
        space_h = (ROOT/"modules/godot_physics_3d/godot_space_3d.h").read_text()
        space_cpp = (ROOT/"modules/godot_physics_3d/godot_space_3d.cpp").read_text()
        server = (ROOT/"servers/physics_3d/physics_server_3d.cpp").read_text()
        helper = (ROOT/"servers/physics_softbody_pair_ccd.h").read_text()
        self.assertIn('soft_body_pair_collision_ccd"), false)', server)
        self.assertIn('bool soft_body_pair_collision_ccd = false;', space_h)
        self.assertIn('soft_body_pair_collision_ccd = GLOBAL_GET(', space_cpp)
        self.assertIn('LocalVector<Vector3> pair_ccd_previous;', soft_h)
        self.assertIn('pair_ccd_previous.reset();', soft)
        self.assertIn('pair_ccd_previous[node.index] = node.x;', soft)
        self.assertIn('refresh_pair_ccd_swept_bounds();', soft)
        self.assertIn('update_pair_swept_face_tree(p_thickness);', soft)
        self.assertIn('p_faces.face_tree.aabb_query(swept_query, visit_face);', soft)
        self.assertIn('physics_xpbd_swept_vertex_triangle(', soft)
        self.assertIn('physics_softbody_solve_pair_swept_face(', soft)
        self.assertIn('physics_xpbd_solve_swept_vertex_face(', helper)
        self.assertIn('pair_ccd ? a->get_pair_swept_bounds()', step)
        self.assertLess(soft.index('pair_ccd_previous[node.index] = node.x;'),
                        soft.index('void GodotSoftBody3D::solve_constraints('))
        self.assertLess(soft.index('physics_xpbd_swept_vertex_triangle('),
                        soft.index('physics_softbody_solve_pair_swept_face('))


if __name__ == "__main__":
    unittest.main()
