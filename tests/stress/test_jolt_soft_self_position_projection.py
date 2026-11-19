"""Independent compliance-weighted Jacobi self-contact position contracts.

These tests verify math and source wiring, NOT native C++ execution.
The solver uses a one-pass XPBD-style lambda with no lambda warm start.
"""
import math
import random
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPACE = ROOT / "modules/jolt_physics/spaces/jolt_space_3d.cpp"
SETTINGS = ROOT / "modules/jolt_physics/jolt_project_settings.cpp"
HEADER = ROOT / "modules/jolt_physics/jolt_project_settings.h"
PROJECT = ROOT / "tests/stress/jolt_soft_self_position/project.godot"
SCENE = ROOT / "tests/stress/jolt_soft_self_position/position_projection_regression.gd"


def one_contact(indices, gradients, inverse_masses, normal, penetration,
                dt=1/60, compliance=0, max_correction=.02):
    """Return per-particle Jacobi delta from an XPBD-style positional contact."""
    result = [(0., 0., 0.) for _ in inverse_masses]
    if penetration <= 0 or dt <= 0 or max_correction <= 0:
        return result
    norm = math.sqrt(sum(x*x for x in normal))
    if not math.isfinite(norm) or norm <= 1e-6:
        return result
    mass_term = sum(g*g*inverse_masses[idx] for idx, g in zip(indices, gradients))
    maximum = max(abs(g)*inverse_masses[idx] for idx, g in zip(indices, gradients))
    if mass_term <= 0 or maximum <= 0:
        return result
    alpha = compliance/(dt*dt)
    lam = min(penetration/(mass_term+alpha), max_correction/maximum)
    for idx, g in zip(indices, gradients):
        result[idx] = tuple(
            result[idx][k] + normal[k] / norm * g*inverse_masses[idx]*lam
            for k in range(3)
        )
    return result


def apply_jacobi(positions, old_positions, inverse_masses, deltas, max_correction=.02):
    """Scale all displacements together, preserving internal center of mass."""
    assert len(positions) == len(deltas)
    longest = max((math.sqrt(sum(x*x for x in p)) for p in deltas), default=0.)
    scale = min(1., max_correction/longest) if longest else 1.
    position_new, history_new = [], []
    for i, (p, previous, delta) in enumerate(zip(positions, old_positions, deltas)):
        moved = tuple(delta[k]*scale for k in range(3)) if inverse_masses[i] > 0 else (0.,0.,0.)
        position_new.append(tuple(p[k]+moved[k] for k in range(3)))
        history_new.append(tuple(previous[k]+moved[k] for k in range(3)))
    return position_new, history_new


def add(a, b):
    return [tuple(x+y for x, y in zip(v, w)) for v, w in zip(a, b)]


class SoftSelfPositionProjectionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.space = SPACE.read_text(encoding="utf-8")
        cls.settings = SETTINGS.read_text(encoding="utf-8")
        cls.header = HEADER.read_text(encoding="utf-8")
        cls.prep = cls.space.split("static bool prepare_soft_self_position_projection(", 1)[1].split(
            "static void accumulate_soft_self_position_projection(", 1
        )[0]
        cls.accum = cls.space.split("static void accumulate_soft_self_position_projection(", 1)[1].split(
            "static void apply_soft_self_position_projection(", 1
        )[0]
        cls.apply = cls.space.split("static void apply_soft_self_position_projection(", 1)[1].split(
            "static uint64_t soft_self_topology_edge_key(", 1
        )[0]
        cls.vf = cls.space.split("static void resolve_soft_body_self_contacts(", 1)[1].split(
            "static bool soft_self_edges_are_neighbors(", 1
        )[0]
        cls.ee = cls.space.split("static void resolve_soft_body_self_edge_contacts(", 1)[1].split(
            "static void clear_pending_index(", 1
        )[0]
        cls.prestep = cls.space.split("void JoltSpace3D::_pre_step(float p_step) {", 1)[1].split(
            "void JoltSpace3D::_post_step(float p_step) {", 1
        )[0]

    def test_stationary_folded_face_separates_without_velocity_recovery(self):
        inv = [1., 1., 1., 1.]
        bary = [.2, .3, .5]
        correction = one_contact([0,1,2,3], [1., *(-v for v in bary)],
                                 inv, (0,1,0), .065, compliance=0, max_correction=.1)
        self.assertGreater(correction[0][1], 0)
        self.assertTrue(all(v[1] < 0 for v in correction[1:]))
        # The barycentric gap increases by exactly the overlap with zero
        # compliance and no max cap.
        improvement = correction[0][1] - sum(bary[i]*correction[i+1][1] for i in range(3))
        self.assertAlmostEqual(improvement, .065, places=10)

    def test_compliance_softens_correction(self):
        inv = [1., 1., 1., 1.]
        grad = [1., -.25, -.25, -.5]
        # Keep the per-contact safety cap inactive in this test so
        # compliance, rather than the clamp, controls the displacement.
        hard = one_contact([0,1,2,3], grad, inv, (0,1,0), .06,
                           compliance=0, max_correction=.1)
        soft = one_contact([0,1,2,3], grad, inv, (0,1,0), .06,
                           compliance=.0001, max_correction=.1)
        self.assertGreater(hard[0][1], soft[0][1])
        self.assertGreater(soft[0][1], 0)

    def test_pinned_vertices_do_not_move(self):
        inv = [0., 1., 1., 0.]
        result = one_contact([0,1,2,3], [1., -.2, -.3, -.5],
                             inv, (0,1,0), .07, max_correction=.04)
        self.assertEqual(result[0], (0,0,0))
        self.assertEqual(result[3], (0,0,0))
        self.assertLess(result[1][1], 0.)
        self.assertLess(result[2][1], 0.)

    def test_all_pinned_or_separate_contacts_do_nothing(self):
        gradient = [1., -.2, -.3, -.5]
        self.assertEqual(one_contact([0,1,2,3], gradient, [0.]*4,
                                     (0,1,0), .06), [(0.,0.,0.)]*4)
        self.assertEqual(one_contact([0,1,2,3], gradient, [1.]*4,
                                     (0,1,0), 0.), [(0.,0.,0.)]*4)

    def test_crossing_edges_have_opposite_displacements(self):
        correction = one_contact([0,1,2,3], [-.5,-.5,.5,.5],
                                 [1.]*4, (0,0,1), .12, max_correction=.1)
        self.assertTrue(all(x[2] < 0 for x in correction[:2]))
        self.assertTrue(all(x[2] > 0 for x in correction[2:]))
        self.assertAlmostEqual(sum(x[2] for x in correction), 0., places=12)

    def test_four_particle_center_of_mass_is_preserved(self):
        inv = [1.4, 2.1, 3.5, .7]
        grad = [-.6, -.4, .35, .65]
        correction = one_contact([0,1,2,3], grad, inv, (0,0,1), .07,
                                 compliance=1e-6, max_correction=.04)
        self.assertAlmostEqual(sum(correction[i][2]/inv[i] for i in range(4)), 0., places=12)

    def test_global_cap_preserves_barycentric_momentum(self):
        inverse = [1., 2., 1., 3.]
        one = one_contact([0,1,2,3], [1.,-.2,-.3,-.5], inverse,
                          (0,1,0), .09, max_correction=.04)
        accumulated = [(v[0], v[1]*10., v[2]) for v in one]
        zero = [(0.,0.,0.)]*4
        current, previous = apply_jacobi(zero, zero, inverse, accumulated, max_correction=.02)
        self.assertLessEqual(max(math.dist(v, (0,0,0)) for v in current), .0200000001)
        self.assertAlmostEqual(sum(current[i][1]/inverse[i] for i in range(4)), 0., places=11)
        self.assertEqual(current, previous)

    def test_history_shift_does_not_inject_velocity(self):
        old = [(0.,0.,0.)]*4
        new = [(0., .3, 0.)]*4
        inverse = [1.,1.,1.,0.]
        corrections = [(0., .01, 0.), (0., -.01, 0.), (0., 0., 0.), (0., 0., 0.)]
        positions, history = apply_jacobi(new, old, inverse, corrections)
        for a, b in zip(positions, history):
            self.assertAlmostEqual(a[1]-b[1], .3)
        self.assertEqual(positions[3], new[3])

    def test_random_multiple_contacts_have_safe_global_cap(self):
        rng = random.Random(327)
        count = 48
        inverse = [rng.choice([0., .4, .8, 1.]) for _ in range(count)]
        all_deltas = [(0.,0.,0.) for _ in range(count)]
        for _ in range(240):
            indices = rng.sample(range(count), 4)
            bary = [rng.random() for _ in range(3)]
            total = sum(bary)
            grad = [1.] + [-x/total for x in bary]
            correction = one_contact(indices, grad, inverse, (0,1,0),
                                     rng.uniform(.001, .08), compliance=1e-6)
            all_deltas = add(all_deltas, correction)
        zero = [(0.,0.,0.) for _ in range(count)]
        positions, history = apply_jacobi(zero, zero, inverse, all_deltas, .02)
        self.assertTrue(all(math.dist(p,(0.,0.,0.)) <= .020000001 for p in positions))
        self.assertEqual(positions, history)
        self.assertAlmostEqual(sum(positions[i][1]/inverse[i]
                                   for i in range(count) if inverse[i] > 0), 0., delta=1e-10)

    def test_default_off_and_finite_clamped_settings(self):
        self.assertIn("inline static bool soft_body_self_position_projection = false;", self.header)
        self.assertIn("soft_body_self_position_compliance = 0.000001f;", self.header)
        self.assertIn("soft_body_self_position_max_correction = 0.02f;", self.header)
        for name in ["soft_body_self_position_projection", "soft_body_self_position_compliance",
                     "soft_body_self_position_max_correction"]:
            self.assertIn('simulation/'+name, self.settings)
        self.assertIn("Math::is_finite(position_compliance)", self.settings)
        self.assertIn("Math::is_finite(max_position_correction)", self.settings)
        self.assertIn("CLAMP(position_compliance, 0.0f, 0.001f)", self.settings)
        self.assertIn("CLAMP(max_position_correction, 0.0f, 0.1f)", self.settings)

    def test_work_budget_memory_and_no_live_query_mutations(self):
        self.assertIn("MAX_SOFT_SELF_POSITION_VERTICES = 4096", self.space)
        self.assertIn("const uint32_t work = 2 * count;", self.prep)
        self.assertIn("r_budget -= work;", self.prep)
        self.assertIn("r_scratch.position_deltas.resize(count)", self.prep)
        self.assertIn("r_scratch.position_projection_ready = false;", self.prep)
        self.assertIn("for (JPH::Vec3 &delta : r_scratch.position_deltas)", self.prep)
        self.assertIn("r_scratch.position_deltas[p_indices[i]] += normal * scale;", self.accum)
        self.assertIn("const float lambda = MIN(p_penetration / denominator, max_correction / max_weighted_inverse_mass);", self.accum)
        self.assertIn("vertex.mPreviousPosition += delta;", self.apply)
        self.assertIn("vertex.mPosition += delta;", self.apply)
        self.assertIn("maximum_sq > limit_sq ? max_correction / Math::sqrt(maximum_sq)", self.apply)

    def test_self_contact_constraints_use_correct_signed_gradients(self):
        self.assertIn("const float gradients[4] = { 1.0f, -u, -v, -w };", self.vf)
        self.assertIn("const float gradients[4] = { -wa0, -wa1, wb0, wb1 };", self.ee)
        self.assertIn("soft_self_is_neighbor(i, face", self.vf)
        self.assertIn("soft_self_edges_are_neighbors(key_a, key_b, edges)", self.ee)
        self.assertIn("accumulate_soft_self_position_projection(r_scratch, vertices, indices, gradients,", self.vf)
        self.assertIn("accumulate_soft_self_position_projection(r_scratch, vertices, indices, gradients,", self.ee)

    def test_projection_applied_after_both_contact_passes(self):
        self.assertIn("scratch->position_projection_ready = false;", self.prestep)
        self.assertIn("prepare_soft_self_position_projection(props.GetVertices(), self_budget, *scratch);", self.prestep)
        self.assertIn("apply_soft_self_position_projection(*jolt_body, *scratch);", self.prestep)
        self.assertLess(self.prestep.index("prepare_soft_self_position_projection("),
                        self.prestep.index("resolve_soft_body_self_contacts(*jolt_body"))
        self.assertLess(self.prestep.index("resolve_soft_body_self_contacts(*jolt_body"),
                        self.prestep.index("resolve_soft_body_self_edge_contacts(*jolt_body"))
        self.assertLess(self.prestep.index("resolve_soft_body_self_edge_contacts(*jolt_body"),
                        self.prestep.index("apply_soft_self_position_projection(*jolt_body"))
        self.assertLess(self.prestep.index("apply_soft_self_position_projection(*jolt_body"),
                        self.prestep.index("physics_system->SetBodyActivationListener("))

    def test_native_fixture_isolates_position_solver_without_velocity_recovery(self):
        project = PROJECT.read_text(encoding="utf-8")
        scene = SCENE.read_text(encoding="utf-8")
        self.assertIn("soft_body_self_position_projection=true", project)
        self.assertIn("soft_body_soft_contact_recovery=0.0", project)
        self.assertIn("soft_body_self_position_compliance=0.0", project)
        self.assertIn("soft_body_self_edge_contacts=true", project)
        self.assertIn("_folded_faces()", scene)
        self.assertIn("_crossed_edges()", scene)
        self.assertIn("_adjacent_control()", scene)
        self.assertIn("PASS: Jolt compliant Jacobi self-contact position projection", scene)


if __name__ == "__main__":
    unittest.main()
