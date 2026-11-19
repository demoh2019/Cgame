"""Reference geometry and source contracts for Jolt soft-soft vertex-face contacts.

Run: python3 -m unittest tests/stress/test_jolt_soft_soft_vertex_face.py -v
Native collision dynamics still require a built Cgame Jolt editor.
"""
from pathlib import Path
import math
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPACE = ROOT / "modules/jolt_physics/spaces/jolt_space_3d.cpp"
SETTINGS = ROOT / "modules/jolt_physics/jolt_project_settings.cpp"
HEADER = ROOT / "modules/jolt_physics/jolt_project_settings.h"
PROJECT = ROOT / "tests/stress/jolt_soft_soft_vertex_face/project.godot"
SCENE = ROOT / "tests/stress/jolt_soft_soft_vertex_face/vertex_face_regression.gd"


def sub(a, b):
    return tuple(x - y for x, y in zip(a, b))


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def cross(a, b):
    return (
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    )


def closest_point_barycentric(p, a, b, c):
    """Independent Ericson triangle Voronoi-region reference."""
    ab, ac = sub(b, a), sub(c, a)
    if dot(cross(ab, ac), cross(ab, ac)) < 1e-14:
        return None
    ap = sub(p, a)
    d1, d2 = dot(ab, ap), dot(ac, ap)
    if d1 <= 0 and d2 <= 0:
        weights = (1., 0., 0.)
    else:
        bp = sub(p, b)
        d3, d4 = dot(ab, bp), dot(ac, bp)
        if d3 >= 0 and d4 <= d3:
            weights = (0., 1., 0.)
        else:
            vc = d1 * d4 - d3 * d2
            if vc <= 0 and d1 >= 0 and d3 <= 0:
                v = d1 / (d1 - d3)
                weights = (1 - v, v, 0.)
            else:
                cp = sub(p, c)
                d5, d6 = dot(ab, cp), dot(ac, cp)
                if d6 >= 0 and d5 <= d6:
                    weights = (0., 0., 1.)
                else:
                    vb = d5 * d2 - d1 * d6
                    if vb <= 0 and d2 >= 0 and d6 <= 0:
                        w = d2 / (d2 - d6)
                        weights = (1 - w, 0., w)
                    else:
                        va = d3 * d6 - d5 * d4
                        if va <= 0 and d4 - d3 >= 0 and d5 - d6 >= 0:
                            w = (d4 - d3) / ((d4 - d3) + (d5 - d6))
                            weights = (0., 1 - w, w)
                        else:
                            denom = va + vb + vc
                            if denom <= 0:
                                return None
                            v, w = vb / denom, vc / denom
                            weights = (1 - v - w, v, w)
    return tuple(sum(weights[j] * point[i] for j, point in enumerate((a, b, c))) for i in range(3)), weights


class VertexFaceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.code = SPACE.read_text(encoding="utf-8")
        cls.settings = SETTINGS.read_text(encoding="utf-8")
        cls.header = HEADER.read_text(encoding="utf-8")
        cls.closest = cls.code.split("static bool closest_soft_triangle_point(", 1)[1].split(
            "static void resolve_soft_soft_vertex_face_direction(", 1
        )[0]
        cls.solver = cls.code.split("static void resolve_soft_soft_vertex_face_direction(", 1)[1].split(
            "static void resolve_soft_soft_vertex_face_contacts(", 1
        )[0]
        cls.prestep = cls.code.split("void JoltSpace3D::_pre_step(float p_step) {", 1)[1].split(
            "void JoltSpace3D::_post_step(", 1
        )[0]

    def test_interior_barycentric_projection(self):
        hit, (u, v, w) = closest_point_barycentric(
            (.2, .3, .07), (0, 0, 0), (1, 0, 0), (0, 1, 0)
        )
        self.assertAlmostEqual(u, .5)
        self.assertAlmostEqual(v, .2)
        self.assertAlmostEqual(w, .3)
        for x, expected in zip(hit, (.2, .3, 0)):
            self.assertAlmostEqual(x, expected)

    def test_vertex_and_edge_voronoi_regions(self):
        tri = ((0, 0, 0), (1, 0, 0), (0, 1, 0))
        cases = [
            ((-.5, -.2, 0), (1, 0, 0)),
            ((1.5, -.2, 0), (0, 1, 0)),
            ((-.2, 1.5, 0), (0, 0, 1)),
            ((.6, -.3, 0), (.4, .6, 0)),
            ((-.2, .6, 0), (.4, 0, .6)),
            ((.7, .7, 0), (0, .5, .5)),
        ]
        for p, expected in cases:
            closest, weights = closest_point_barycentric(p, *tri)
            self.assertAlmostEqual(sum(weights), 1.0)
            for a, b in zip(weights, expected):
                self.assertAlmostEqual(a, b)
            self.assertTrue(all(math.isfinite(x) for x in closest))

    def test_reject_degenerate_faces(self):
        self.assertIsNone(closest_point_barycentric((0, 0, .1), (0, 0, 0), (0, 0, 0), (1, 0, 0)))
        self.assertIsNone(closest_point_barycentric((0, 0, .1), (0, 0, 0), (1, 0, 0), (2, 0, 0)))

    def test_effective_mass_and_equal_opposite_impulse(self):
        weights = [.5, .3, .2]
        inv_point = 2.0
        inverse_face = [0.0, 1.0, 4.0]
        effective = inv_point + sum(w * w * im for w, im in zip(weights, inverse_face))
        self.assertGreater(effective, inv_point)
        impulse = 2.1 / effective
        v_point = inv_point * impulse
        v_face = [-w * im * impulse for w, im in zip(weights, inverse_face)]
        # Signed momentum of mobile particles (anchored vertex transmits
        # some force to the external kinematic constraint).
        applied_to_face = sum((v / im) for v, im in zip(v_face, inverse_face) if im)
        self.assertAlmostEqual(applied_to_face, -impulse * .5)
        self.assertAlmostEqual(v_point / inv_point, impulse)
        self.assertAlmostEqual(effective, 2.0 + .09 + .16)

    def test_all_movable_face_vertices_preserve_net_momentum(self):
        weights = [.2, .3, .5]
        inverse_masses = [1.0, 2.0, 5.0]
        impulse = 3.4
        momentum_point = impulse
        momentum_face = sum((-w * im * impulse) / im for w, im in zip(weights, inverse_masses))
        self.assertAlmostEqual(momentum_point + momentum_face, 0.0)

    def test_pinned_vertex_remains_unchanged(self):
        self.assertIn("u * v0.mInvMass", self.solver)
        self.assertIn("v * v1.mInvMass", self.solver)
        self.assertIn("w * v2.mInvMass", self.solver)
        self.assertIn("point.mVelocity += inv_point_rotation * (impulse * point.mInvMass);", self.solver)
        self.assertIn("v0.mVelocity -= local_face_impulse * (u * v0.mInvMass);", self.solver)

    def test_mode_preserves_old_vertex_vertex_fast_path(self):
        self.assertIn("inline static bool soft_body_soft_vertex_face_contacts = false;", self.header)
        self.assertIn('simulation/soft_body_soft_vertex_face_contacts"), false', self.settings)
        self.assertIn("if (JoltProjectSettings::soft_body_soft_vertex_face_contacts)", self.prestep)
        self.assertIn("resolve_soft_soft_particle_contacts(", self.prestep)
        self.assertIn("resolve_soft_soft_vertex_face_contacts(", self.prestep)

    def test_checks_both_body_directions_and_contact_filters(self):
        self.assertIn("resolve_soft_soft_vertex_face_direction(p_body_a, p_body_b", self.code)
        self.assertIn("resolve_soft_soft_vertex_face_direction(p_body_b, p_body_a", self.code)
        self.assertIn("object_a->can_interact_with(*object_b)", self.prestep)
        self.assertIn("bounds_a.intersects(", self.prestep)

    def test_bounded_work_and_finite_guards(self):
        self.assertIn("--r_contact_budget;", self.solver)
        self.assertIn("if (r_contact_budget == 0)", self.solver)
        self.assertIn("!Math::is_finite(inverse_mass_sum)", self.solver)
        self.assertIn("!Math::is_finite(normal_speed)", self.solver)
        self.assertIn("Math::is_finite(tangent_speed_sq)", self.solver)
        self.assertIn("MAX_SOFT_SOFT_CONTACT_SPEED_CORRECTION", self.solver)
        self.assertIn("p_step > 0.0f", self.prestep)

    def test_project_has_sparse_face_and_masked_control(self):
        cfg = PROJECT.read_text(encoding="utf-8")
        src = SCENE.read_text(encoding="utf-8")
        self.assertIn("soft_body_soft_contacts=true", cfg)
        self.assertIn("soft_body_soft_vertex_face_contacts=true", cfg)
        self.assertIn("soft_body_soft_contact_max_particle_pairs=16384", cfg)
        self.assertIn("_plane_mesh(6.0)", src)
        self.assertIn("masked_lift", src)
        self.assertIn("PASS: Jolt sparse soft-soft vertex-face contacts and masked control", src)


if __name__ == "__main__":
    unittest.main()
