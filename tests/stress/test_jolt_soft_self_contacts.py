"""Jolt opt-in soft body self-collision: independent topology/momentum tests.

These reference tests validate contracts but are NOT native C++ physics tests.
Native scene: tests/stress/jolt_soft_self/self_collision_regression.gd.
"""
from pathlib import Path
import math
import unittest

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "modules/jolt_physics/spaces/jolt_space_3d.cpp"
SETTINGS = ROOT / "modules/jolt_physics/jolt_project_settings.cpp"
HEADER = ROOT / "modules/jolt_physics/jolt_project_settings.h"
PROJECT = ROOT / "tests/stress/jolt_soft_self/project.godot"
NATIVE = ROOT / "tests/stress/jolt_soft_self/self_collision_regression.gd"


def one_ring_edges(faces):
    result = set()
    for a, b, c in faces:
        if len({a, b, c}) < 3:
            continue
        for i, j in ((a, b), (b, c), (c, a)):
            result.add(tuple(sorted((i, j))))
    return sorted(result)


def is_neighbor(point, face, edges):
    links = set(edges)
    return any(point == corner or tuple(sorted((point, corner))) in links
               for corner in face)


def impulse_response(vp, va, vb, vc, mp, ma, mb, mc,
                     bary, normal, distance, radius=.12, dt=1/60,
                     recovery=.4, friction=.2):
    """One-axis normal impulse reference; pinned inverse masses are zero."""
    u, v, w = bary
    inv = mp + u*u*ma + v*v*mb + w*w*mc
    if inv <= 0 or distance >= radius:
        return (vp, va, vb, vc)
    face_velocity = u*va + v*vb + w*vc
    closing_velocity = (vp - face_velocity) * normal
    correction = min(max(min((radius-distance)*recovery/dt, 2.0)
                         - closing_velocity, 0.0), 8.0)
    impulse = normal * correction / inv
    return (vp + mp * impulse,
            va - u * ma * impulse,
            vb - v * mb * impulse,
            vc - w * mc * impulse)


class SoftSelfContactReferenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.src = SOURCE.read_text(encoding="utf-8")
        cls.settings = SETTINGS.read_text(encoding="utf-8")
        cls.header = HEADER.read_text(encoding="utf-8")
        cls.topology = cls.src.split("static bool prepare_soft_self_topology(", 1)[1].split(
            "static bool soft_self_is_neighbor(", 1
        )[0]
        cls.filter = cls.src.split("static bool soft_self_is_neighbor(", 1)[1].split(
            "static void resolve_soft_body_self_contacts(", 1
        )[0]
        cls.solver = cls.src.split("static void resolve_soft_body_self_contacts(", 1)[1].split(
            "static void clear_pending_index(", 1
        )[0]
        cls.prestep = cls.src.split("void JoltSpace3D::_pre_step(float p_step) {", 1)[1].split(
            "void JoltSpace3D::_post_step(float p_step) {", 1
        )[0]

    def test_same_face_and_one_ring_neighbors_are_rejected(self):
        faces = [(0, 1, 2), (1, 3, 2)]
        edges = one_ring_edges(faces)
        for point in range(4):
            for face in faces:
                self.assertTrue(is_neighbor(point, face, edges))
        self.assertEqual(edges, [(0, 1), (0, 2), (1, 2), (1, 3), (2, 3)])

    def test_nonadjacent_folded_layers_are_eligible(self):
        faces = [(0, 1, 2), (3, 5, 4)]
        edges = one_ring_edges(faces)
        for point in (0, 1, 2):
            self.assertFalse(is_neighbor(point, faces[1], edges))
        for point in (3, 4, 5):
            self.assertFalse(is_neighbor(point, faces[0], edges))
        self.assertEqual(len(edges), 6)

    def test_degenerate_triangles_skipped(self):
        faces = [(0, 1, 2), (3, 3, 4), (2, 2, 2)]
        self.assertEqual(len(one_ring_edges(faces)), 3)
        self.assertIn("face.IsDegenerate()", self.topology)
        self.assertIn("face.IsDegenerate()", self.solver)

    def test_undirected_sorted_edge_encoding_deduplicates(self):
        faces = [(0, 1, 2), (2, 1, 3), (3, 1, 2)]
        self.assertEqual(len(one_ring_edges(faces)), 5)
        self.assertIn("std::sort(r_edges.begin(), r_edges.end());", self.topology)
        self.assertIn("std::unique(r_edges.begin(), r_edges.end())", self.topology)
        self.assertIn("std::binary_search(", self.filter)
        self.assertIn("soft_self_topology_edge_key(p_point, face_vertex)", self.filter)

    def test_one_body_four_particle_mass_weighted_momentum(self):
        u, v, w = .2, .3, .5
        inv = [2., 1., 3., 4.]
        mass_sum = inv[0] + u*u*inv[1] + v*v*inv[2] + w*w*inv[3]
        j = 4.0 / mass_sum
        velocity_change = [j*inv[0], -j*u*inv[1], -j*v*inv[2], -j*w*inv[3]]
        total_momentum_change = sum(d/m for d, m in zip(velocity_change, inv))
        self.assertAlmostEqual(total_momentum_change, 0., places=12)
        self.assertAlmostEqual(mass_sum, 2.0 + .04 + .27 + 1.0)
        self.assertIn("point.mVelocity += impulse * point.mInvMass;", self.solver)
        self.assertIn("a.mVelocity -= impulse * (u * a.mInvMass);", self.solver)
        self.assertIn("c.mVelocity -= impulse * (w * c.mInvMass);", self.solver)

    def test_finite_penetration_pushes_nonadjacent_surfaces_apart(self):
        # Vertex above the opposite face, both initially stationary.
        v = impulse_response(0., 0., 0., 0., 1., 1., 1., 1.,
                             (.2, .3, .5), 1., .055)
        self.assertGreater(v[0], 0.)
        self.assertLess(v[1], 0.)
        self.assertLess(v[2], 0.)
        self.assertLess(v[3], 0.)
        self.assertAlmostEqual(sum(v), 0., places=10)
        self.assertTrue(all(math.isfinite(x) for x in v))

    def test_pinned_particle_and_all_pinned_face_handled(self):
        # Pinned point does not move, dynamic face takes the impulse.
        v = impulse_response(0., 0., 0., 0., 0., 1., 1., 1.,
                             (.2, .3, .5), 1., .05)
        self.assertEqual(v[0], 0.)
        self.assertLess(v[1], 0.)
        # Fully pinned node and fully pinned face => zero contact.
        a = impulse_response(0., 0., 0., 0., 0., 0., 0., 0.,
                             (.2, .3, .5), 1., .05)
        self.assertEqual(a, (0., 0., 0., 0.))

    def test_contact_outside_radius_does_nothing(self):
        result = impulse_response(0., 0., 0., 0., 1., 1., 1., 1.,
                                  (.2, .3, .5), 1., .22)
        self.assertEqual(result, (0., 0., 0., 0.))
        self.assertIn("distance_sq >= radius_sq", self.solver)

    def test_topology_and_bvh_use_bounded_work(self):
        self.assertIn("MAX_SOFT_SELF_CONTACT_FACES = 1024", self.src)
        self.assertIn("const uint32_t build_cost = raw_count * (levels + 1);", self.topology)
        self.assertIn("r_budget -= build_cost;", self.topology)
        self.assertIn("!ensure_soft_self_topology(", self.solver)
        self.assertIn("prepare_soft_face_bvh(faces, vertices, JPH::Quat::sIdentity()", self.solver)
        self.assertIn("if (needs_bvh && !use_bvh)", self.solver)
        self.assertIn("query_soft_face_bvh(", self.solver)
        self.assertIn("--r_budget; // Count all candidate checks", self.solver)
        self.assertIn("for (uint32_t i = 0; i < particle_count && r_budget > 0;", self.solver)

    def test_all_adjacency_exclusions_precede_impulse_math(self):
        self.assertLess(self.solver.index("soft_self_is_neighbor(i, face,"),
                        self.solver.index("const float inverse_mass_sum"))
        self.assertLess(self.solver.index("--r_budget; // Count all"),
                        self.solver.index("soft_self_is_neighbor(i, face"))
        self.assertIn("soft_self_is_neighbor(i, face, r_scratch.one_ring_edges)", self.solver)

    def test_opt_in_master_independence_and_project_settings(self):
        self.assertIn("inline static bool soft_body_self_contacts = false;", self.header)
        self.assertIn("inline static int soft_body_self_contact_max_checks = 16384;", self.header)
        self.assertIn('simulation/soft_body_self_contacts"), false', self.settings)
        self.assertIn('simulation/soft_body_self_contact_max_checks", PROPERTY_HINT_RANGE, "1024,65536,1024"), 16384', self.settings)
        self.assertIn("CLAMP((int)GLOBAL_GET", self.settings)
        self.assertIn("if (JoltProjectSettings::soft_body_self_contacts &&", self.prestep)
        self.assertIn("SoftSelfContactScratch self_scratch;", self.prestep)
        self.assertIn("resolve_soft_body_self_contacts(*jolt_body, *object, p_step, self_budget, *scratch);", self.prestep)
        self.assertLess(self.prestep.index("resolve_soft_body_self_contacts("),
                        self.prestep.index("if (JoltProjectSettings::soft_body_soft_contacts &&"))

    def test_native_fixture_includes_connected_quad_and_folded_sheet(self):
        cfg = PROJECT.read_text(encoding="utf-8")
        scene = NATIVE.read_text(encoding="utf-8")
        self.assertIn("soft_body_self_contacts=true", cfg)
        self.assertIn("soft_body_soft_contacts=false", cfg)
        self.assertIn("_folded_sheet()", scene)
        self.assertIn("_adjacent_control()", scene)
        self.assertIn("start_gap", scene)
        self.assertIn("end_gap", scene)
        self.assertIn("control_drift", scene)
        self.assertIn("PASS: Jolt nonlocal soft self collision and one-ring suppression", scene)


if __name__ == "__main__":
    unittest.main()
