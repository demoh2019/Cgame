"""Reference segment geometry, impulse invariants and Cgame Jolt contracts.

This does not execute the C++ physics engine. Native scene:
tests/stress/jolt_soft_soft_edges/edge_edge_regression.gd
"""
import math
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPACE = ROOT / "modules/jolt_physics/spaces/jolt_space_3d.cpp"
CONFIG = ROOT / "modules/jolt_physics/jolt_project_settings.cpp"
HEADER = ROOT / "modules/jolt_physics/jolt_project_settings.h"
NATIVE = ROOT / "tests/stress/jolt_soft_soft_edges/edge_edge_regression.gd"
PROJECT = ROOT / "tests/stress/jolt_soft_soft_edges/project.godot"


def dot(a, b):
    return sum(x*y for x, y in zip(a, b))


def sub(a, b):
    return tuple(x-y for x, y in zip(a, b))


def add_scaled(a, d, t):
    return tuple(x+t*y for x, y in zip(a, d))


def closest_segments(p0, p1, q0, q1):
    d1, d2, r = sub(p1, p0), sub(q1, q0), sub(p0, q0)
    a, e = dot(d1, d1), dot(d2, d2)
    if a <= 1e-12 or e <= 1e-12:
        return None
    b, c, f = dot(d1, d2), dot(d1, r), dot(d2, r)
    denom = a*e - b*b
    s = max(0., min(1., (b*f-c*e)/denom)) if denom > 1e-12 else 0.
    t = (b*s+f)/e
    if t < 0:
        t, s = 0., max(0., min(1., -c/a))
    elif t > 1:
        t, s = 1., max(0., min(1., (b-c)/a))
    return s, t, add_scaled(p0, d1, s), add_scaled(q0, d2, t)


def face_keys(faces):
    keys = []
    for a, b, c in faces:
        if len({a, b, c}) != 3:
            continue
        for x, y in ((a, b), (b, c), (c, a)):
            keys.append((min(x, y), max(x, y)))
    return sorted(set(keys))


class SoftEdgeEdgeReferenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.code = SPACE.read_text(encoding="utf-8")
        cls.settings = CONFIG.read_text(encoding="utf-8")
        cls.header = HEADER.read_text(encoding="utf-8")
        cls.solver = cls.code.split("static void resolve_soft_soft_edge_edge_contacts(", 1)[1].split(
            "static void clear_pending_index(", 1
        )[0]
        cls.closest = cls.code.split("static bool closest_soft_edge_edge(", 1)[1].split(
            "static void resolve_soft_soft_edge_edge_contacts(", 1
        )[0]
        cls.prestep = cls.code.split("void JoltSpace3D::_pre_step(float p_step) {", 1)[1].split(
            "void JoltSpace3D::_post_step(", 1
        )[0]

    def test_perpendicular_crossing_edges_no_nearby_endpoints(self):
        p0, p1 = (-0.9, 0, 0), (0.9, 0, 0)
        q0, q1 = (0, -0.9, 0), (0, 0.9, 0)
        s, t, p, q = closest_segments(p0, p1, q0, q1)
        self.assertAlmostEqual(s, .5)
        self.assertAlmostEqual(t, .5)
        self.assertEqual(p, q)
        for a in (p0, p1):
            for b in (q0, q1):
                self.assertGreater(math.dist(a, b), 0.16)

    def test_skew_edges_and_clamped_endpoints(self):
        samples = [
            (((-1, 0, 0), (1, 0, 0), (0, -1, .4), (0, 1, .4)), (.5, .5, .4)),
            (((0, 0, 0), (1, 0, 0), (2, 1, 0), (2, 2, 0)), (1., 0., math.sqrt(2))),
            (((0, 0, 0), (1, 0, 0), (0.2, 1, 0), (0.8, 1, 0)), (.2, 0., 1.)),
        ]
        for args, (expected_s, expected_t, distance) in samples:
            s, t, p, q = closest_segments(*args)
            self.assertAlmostEqual(s, expected_s)
            self.assertAlmostEqual(t, expected_t)
            self.assertAlmostEqual(math.dist(p, q), distance)

    def test_degenerate_segments_rejected(self):
        self.assertIsNone(closest_segments((0, 0, 0), (0, 0, 0), (1, 0, 0), (1, 1, 0)))
        self.assertIsNone(closest_segments((0, 0, 0), (1, 0, 0), (0, 0, 0), (0, 0, 0)))
        self.assertIn("a <= SOFT_EDGE_EPSILON || e <= SOFT_EDGE_EPSILON", self.closest)

    def test_welded_surface_edges_are_unique(self):
        self.assertEqual(face_keys([(0, 1, 2), (2, 1, 3)]),
                         [(0, 1), (0, 2), (1, 2), (1, 3), (2, 3)])
        self.assertIn("std::sort(r_keys.begin(), r_keys.end());", self.code)
        self.assertIn("std::unique(r_keys.begin(), r_keys.end())", self.code)
        self.assertIn("r_keys.resize(unique_count);", self.code)

    def test_inverse_mass_momentum_four_moving_vertices(self):
        s, t = .25, .75
        inv = (1., 2., 3., 4.)
        weights = (1-s, s, 1-t, t)
        denom = sum(w*w*im for w, im in zip(weights, inv))
        impulse = 3.2 / denom
        change = [-weights[0]*inv[0]*impulse,
                  -weights[1]*inv[1]*impulse,
                   weights[2]*inv[2]*impulse,
                   weights[3]*inv[3]*impulse]
        momenta = [v/im for v, im in zip(change, inv)]
        self.assertAlmostEqual(sum(momenta), 0.)
        self.assertGreater(denom, 0.)

    def test_kinematic_edge_endpoints_remain_fixed(self):
        s, t = .5, .5
        inv = (0., 1., 0., 2.)
        weights = (1-s, s, 1-t, t)
        denom = sum(w*w*im for w, im in zip(weights, inv))
        self.assertGreater(denom, 0)
        impulse = 1. / denom
        changes = [-weights[0]*inv[0]*impulse, -weights[1]*inv[1]*impulse,
                   weights[2]*inv[2]*impulse, weights[3]*inv[3]*impulse]
        self.assertEqual(changes[0], 0.)
        self.assertEqual(changes[2], 0.)
        self.assertIn("a0.mVelocity -= local_impulse_a * (wa0 * a0.mInvMass)", self.solver)
        self.assertIn("b0.mVelocity += local_impulse_b * (wb0 * b0.mInvMass)", self.solver)

    def test_collision_configuration_is_opt_in(self):
        self.assertIn("inline static bool soft_body_soft_edge_edge_contacts = false;", self.header)
        self.assertIn('simulation/soft_body_soft_edge_edge_contacts"), false', self.settings)
        self.assertIn("soft_body_soft_vertex_face_contacts &&", self.prestep)
        self.assertIn("soft_body_soft_edge_edge_contacts;", self.prestep)

    def test_separate_budget_shared_global_ceiling(self):
        self.assertIn("edge_budget = edge_contacts ? particle_budget / 2 : 0;", self.prestep)
        self.assertIn("particle_budget -= edge_budget;", self.prestep)
        self.assertIn("particle_budget > 0 || edge_budget > 0", self.prestep)
        self.assertIn("MAX_SOFT_SOFT_BODY_PAIR_CHECKS", self.prestep)
        self.assertIn("--r_budget; // Includes rejected candidates", self.solver)
        self.assertIn("r_budget -= construction_cost;", self.code)
        self.assertIn("p_faces.size() > MAX_SOFT_SOFT_EDGE_FACES", self.code)

    def test_finite_controls_and_contact_filters(self):
        self.assertIn("!Math::is_finite(distance_sq)", self.solver)
        self.assertIn("!Math::is_finite(inverse_mass_sum)", self.solver)
        self.assertIn("!Math::is_finite(normal_speed)", self.solver)
        self.assertIn("!Math::is_finite(normal_impulse)", self.solver)
        self.assertIn("object_a->can_interact_with(*object_b)", self.prestep)
        self.assertIn("bounds_a.intersects(", self.prestep)

    def test_native_scene_exercises_crossing_and_masked_control(self):
        cfg = PROJECT.read_text(encoding="utf-8")
        scene = NATIVE.read_text(encoding="utf-8")
        for setting in ("soft_body_soft_contacts=true",
                        "soft_body_soft_vertex_face_contacts=true",
                        "soft_body_soft_edge_edge_contacts=true"):
            self.assertIn(setting, cfg)
        self.assertIn("var allowed_z_gap", scene)
        self.assertIn("var masked_z_gap", scene)
        self.assertIn("PASS: Jolt crossing soft-body edges collide with mask control", scene)


if __name__ == "__main__":
    unittest.main()
