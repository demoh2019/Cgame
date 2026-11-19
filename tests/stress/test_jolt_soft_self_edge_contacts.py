"""Reference topology and mechanics tests for Jolt soft-body self edge collisions.

Run: python3 -m unittest tests/stress/test_jolt_soft_self_edge_contacts.py -v
These tests do not compile or run the engine; the native scene is separate.
"""
from pathlib import Path
import math
import unittest

ROOT = Path(__file__).resolve().parents[2]
CPP = ROOT / "modules/jolt_physics/spaces/jolt_space_3d.cpp"
CONFIG = ROOT / "modules/jolt_physics/jolt_project_settings.cpp"
HEADER = ROOT / "modules/jolt_physics/jolt_project_settings.h"
PROJECT = ROOT / "tests/stress/jolt_soft_self_edges/project.godot"
NATIVE = ROOT / "tests/stress/jolt_soft_self_edges/self_edges_regression.gd"


def keys(faces):
    return sorted(set(tuple(sorted((face[i], face[(i+1) % 3])))
                      for face in faces for i in range(3)
                      if len(set(face)) == 3))


def neighbors(edge_a, edge_b, adjacency):
    if set(edge_a).intersection(edge_b):
        return True
    adjacency = set(adjacency)
    return any(tuple(sorted((a, b))) in adjacency
               for a in edge_a for b in edge_b)


def vsub(a, b):
    return tuple(x-y for x, y in zip(a, b))


def vdot(a, b):
    return sum(x*y for x, y in zip(a, b))


def vscale(v, t):
    return tuple(x*t for x in v)


def vadd(a, b):
    return tuple(x+y for x, y in zip(a, b))


def closest_segment_points(p0, p1, q0, q1):
    d1, d2, r = vsub(p1, p0), vsub(q1, q0), vsub(p0, q0)
    aa, ee = vdot(d1, d1), vdot(d2, d2)
    if not math.isfinite(aa) or not math.isfinite(ee) or min(aa, ee) <= 1e-12:
        return None
    b, c, f = vdot(d1, d2), vdot(d1, r), vdot(d2, r)
    denominator = aa*ee-b*b
    if not all(math.isfinite(x) for x in (denominator, c, f)):
        return None
    s = max(0., min(1., (b*f-c*ee)/denominator)) if denominator > 1e-12 else 0.
    t = (b*s+f)/ee
    if t < 0:
        t, s = 0., max(0., min(1., -c/aa))
    elif t > 1:
        t, s = 1., max(0., min(1., (b-c)/aa))
    return s, t, vadd(p0, vscale(d1, s)), vadd(q0, vscale(d2, t))


class SoftSelfEdgeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cpp = CPP.read_text(encoding="utf8")
        cls.cfg = CONFIG.read_text(encoding="utf8")
        cls.h = HEADER.read_text(encoding="utf8")
        cls.filter = cls.cpp.split("static bool soft_self_edges_are_neighbors(", 1)[1].split(
            "static void resolve_soft_body_self_edge_contacts(", 1
        )[0]
        cls.solver = cls.cpp.split("static void resolve_soft_body_self_edge_contacts(", 1)[1].split(
            "static void clear_pending_index(", 1
        )[0]
        cls.pre = cls.cpp.split("void JoltSpace3D::_pre_step(float p_step) {", 1)[1].split(
            "void JoltSpace3D::_post_step(float p_step) {", 1
        )[0]

    def test_nonlocal_edges_in_one_soft_body_are_eligible(self):
        adjacency = keys([(0, 1, 2), (3, 4, 5)])
        self.assertFalse(neighbors((0, 1), (3, 4), adjacency))
        self.assertEqual(len(adjacency), 6)

    def test_one_ring_connected_quad_excluded(self):
        adjacency = keys([(0, 2, 1), (1, 2, 3)])
        for i, a in enumerate(adjacency):
            for b in adjacency[i+1:]:
                self.assertTrue(neighbors(a, b, adjacency), (a, b))

    def test_shared_endpoint_rejected(self):
        edges = keys([(0, 1, 2), (2, 3, 4)])
        self.assertTrue(neighbors((0, 2), (2, 3), edges))
        self.assertTrue(neighbors((0, 1), (1, 2), edges))

    def test_crossing_edge_geometry(self):
        p0, p1 = (-.9, 2., 0.), (.9, 2., 0.)
        q0, q1 = (0., 1.1, 0.), (0., 2.9, 0.)
        result = closest_segment_points(p0, p1, q0, q1)
        self.assertIsNotNone(result)
        s, t, a, b = result
        self.assertAlmostEqual(s, .5)
        self.assertAlmostEqual(t, .5)
        self.assertAlmostEqual(math.dist(a, b), 0.)
        for a in (p0, p1):
            for b in (q0, q1):
                self.assertGreater(math.dist(a, b), .15)

    def test_skew_parallel_and_degenerate_segments(self):
        a = closest_segment_points((-1, 0, 0), (1, 0, 0), (0, -1, .06), (0, 1, .06))
        self.assertAlmostEqual(math.dist(a[2], a[3]), .06)
        p = closest_segment_points((-1, 0, 0), (1, 0, 0), (-1, .05, 0), (1, .05, 0))
        self.assertAlmostEqual(math.dist(p[2], p[3]), .05)
        self.assertIsNone(closest_segment_points((0, 0, 0), (0, 0, 0), (0, 0, 0), (0, 1, 0)))

    def test_unordered_pairs_only_once(self):
        edges = keys([(0, 1, 2), (3, 4, 5)])
        pairs = [(edges[i], edges[j]) for i in range(len(edges)) for j in range(i+1, len(edges))]
        self.assertEqual(len(pairs), 15)
        self.assertEqual(len(set(pairs)), len(pairs))
        self.assertIn("for (uint32_t candidate = 0; candidate < candidate_count", self.solver)
        self.assertIn("if (j <= i)", self.solver)

    def test_inverse_mass_weights_conserve_momentum(self):
        s, t = .3, .6
        masses_inv = [2., 1., 3., 5.]
        weights = [1-s, s, 1-t, t]
        effective = sum(w*w*m for w, m in zip(weights, masses_inv))
        impulse = 2.8 / effective
        dv = [(-1 if i < 2 else 1)*w*m*impulse
              for i, (w, m) in enumerate(zip(weights, masses_inv))]
        self.assertAlmostEqual(sum(v/m for v, m in zip(dv, masses_inv)), 0.)
        self.assertIn("wa0 * wa0 * a0.mInvMass", self.solver)
        self.assertIn("a0.mVelocity -= impulse * (wa0 * a0.mInvMass);", self.solver)
        self.assertIn("b1.mVelocity += impulse * (wb1 * b1.mInvMass);", self.solver)

    def test_pinned_ends_get_no_velocity(self):
        inv = (0., 1., 0., 2.)
        weights = (.5, .5, .5, .5)
        impulse = 1 / sum(w*w*m for w, m in zip(weights, inv))
        velocity = [w*m*impulse for w, m in zip(weights, inv)]
        self.assertEqual(velocity[0], 0.)
        self.assertEqual(velocity[2], 0.)
        self.assertTrue(all(math.isfinite(x) for x in velocity))

    def test_topology_uses_bisearch_and_local_coordinate_frame(self):
        self.assertIn("soft_self_topology_edge_key(a, b)", self.filter)
        self.assertIn("std::binary_search(", self.filter)
        self.assertIn("if (a0 == b0 || a0 == b1 || a1 == b0 || a1 == b1)", self.filter)
        self.assertIn("const JPH::Vec3 p0 = a0.mPosition;", self.solver)
        self.assertIn("const JPH::Vec3 q0 = b0.mPosition;", self.solver)
        self.assertIn("if (soft_self_edges_are_neighbors(key_a, key_b, edges))", self.solver)

    def test_shared_budget_and_adjacency_reuse(self):
        self.assertIn("self_edge_budget = self_edges ? self_budget / 2 : 0;", self.pre)
        self.assertIn("self_budget -= self_edge_budget;", self.pre)
        self.assertIn("(self_budget > 0 || self_edge_budget > 0)", self.pre)
        self.assertIn("scratch->one_ring_edges.clear();", self.pre)
        self.assertIn("ensure_soft_self_topology(", self.solver)
        self.assertIn("soft_body_self_persistent_bvh", self.solver)
        self.assertIn("--r_budget; // Every tested candidate", self.solver)
        self.assertIn("r_scratch.one_ring_edges", self.solver)

    def test_does_not_require_inter_body_master_and_default_off(self):
        self.assertIn("inline static bool soft_body_self_edge_contacts = false;", self.h)
        self.assertIn('simulation/soft_body_self_edge_contacts"), false', self.cfg)
        self.assertIn("soft_body_self_edge_contacts = GLOBAL_GET(", self.cfg)
        self.assertIn("if (JoltProjectSettings::soft_body_self_contacts &&", self.pre)
        self.assertIn("JoltProjectSettings::soft_body_self_edge_contacts;", self.pre)
        self.assertIn("resolve_soft_body_self_edge_contacts(*jolt_body", self.pre)
        self.assertLess(self.pre.index("resolve_soft_body_self_edge_contacts("),
                        self.pre.index("if (JoltProjectSettings::soft_body_soft_contacts &&"))

    def test_finite_and_degenerate_guards_and_coulomb_friction(self):
        self.assertIn("!closest_soft_edge_edge(p0, p1, q0, q1", self.solver)
        self.assertIn("!Math::is_finite(distance_sq)", self.solver)
        self.assertIn("!Math::is_finite(inverse_mass_sum)", self.solver)
        self.assertIn("!Math::is_finite(normal_speed)", self.solver)
        self.assertIn("!Math::is_finite(normal_impulse)", self.solver)
        self.assertIn("const float tangent_impulse = MIN(", self.solver)
        self.assertIn("MAX_SOFT_SOFT_CONTACT_SPEED_CORRECTION", self.solver)

    def test_native_scene_has_crossing_and_one_ring_control(self):
        project = PROJECT.read_text(encoding="utf8")
        scene = NATIVE.read_text(encoding="utf8")
        self.assertIn("soft_body_self_edge_contacts=true", project)
        self.assertIn("soft_body_soft_contacts=false", project)
        self.assertIn("_crossed_unconnected_triangles()", scene)
        self.assertIn("_connected_quad_control()", scene)
        self.assertIn("max_separation", scene)
        self.assertIn("max_control_drift", scene)
        self.assertIn("PASS: Jolt self edge-edge contacts suppress one-ring adjacency", scene)


if __name__ == "__main__":
    unittest.main()
