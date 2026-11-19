"""Independent linearized swept soft-vertex / moving-triangle reference tests.

This validates geometry and source integration, NOT a native physics runtime.
Run with:
  python3 -m unittest tests/stress/test_jolt_soft_soft_speculative_ccd.py -v
"""
from pathlib import Path
import math
import random
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPACE = ROOT / "modules/jolt_physics/spaces/jolt_space_3d.cpp"
HEADER = ROOT / "modules/jolt_physics/jolt_project_settings.h"
CONFIG = ROOT / "modules/jolt_physics/jolt_project_settings.cpp"
PROJECT = ROOT / "tests/stress/jolt_soft_soft_sweep/project.godot"
FIXTURE = ROOT / "tests/stress/jolt_soft_soft_sweep/swept_triangle_regression.gd"


def add(a, b):
    return tuple(x + y for x, y in zip(a, b))


def sub(a, b):
    return tuple(x - y for x, y in zip(a, b))


def mul(v, t):
    return tuple(x * t for x in v)


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1],
            a[2] * b[0] - a[0] * b[2],
            a[0] * b[1] - a[1] * b[0])


def length(v):
    return math.sqrt(dot(v, v))


def closest_on_triangle_if_inside(p, a, b, c):
    """Independent interior-triangle reference (off-face hits are rejected)."""
    ab, ac = sub(b, a), sub(c, a)
    cross_normal = cross(ab, ac)
    area = length(cross_normal)
    if area < 1e-6:
        return None
    n = mul(cross_normal, 1 / area)
    projected = sub(p, mul(n, dot(sub(p, a), n)))
    d00, d01, d11 = dot(ab, ab), dot(ab, ac), dot(ac, ac)
    d20, d21 = dot(sub(projected, a), ab), dot(sub(projected, a), ac)
    denom = d00 * d11 - d01 * d01
    if denom <= 1e-12:
        return None
    v = (d11 * d20 - d01 * d21) / denom
    w = (d00 * d21 - d01 * d20) / denom
    u = 1 - v - w
    if min(u, v, w) < -1e-8:
        return None
    return projected, (u, v, w)


def predict_sweep(point, point_vel, triangle, face_vels, dt=1 / 60,
                  radius=0.1, max_sweep=1):
    """Reference for the linearized TOI, then moving-face verification."""
    if dt <= 0 or radius <= 0 or max_sweep <= 0:
        return None
    a, b, c = triangle
    va, vb, vc = face_vels
    face_n = cross(sub(b, a), sub(c, a))
    normal_size = length(face_n)
    if normal_size <= 1e-6:
        return None
    normal = mul(face_n, 1 / normal_size)
    face_vel = mul(add(add(va, vb), vc), 1 / 3)
    relative_vel = sub(point_vel, face_vel)
    if not math.isfinite(length(relative_vel)) or length(mul(relative_vel, dt)) > max_sweep:
        return None
    signed_distance = dot(sub(point, a), normal)
    speed = dot(relative_vel, normal)
    if signed_distance > radius and speed < -1e-6:
        target = radius
    elif signed_distance < -radius and speed > 1e-6:
        target = -radius
    else:
        return None
    toi = (target - signed_distance) / speed
    if not math.isfinite(toi) or not (0 <= toi <= dt):
        return None
    hit = add(point, mul(point_vel, toi))
    moved = [add(v, mul(speed_vec, toi)) for v, speed_vec in zip(triangle, face_vels)]
    nearest = closest_on_triangle_if_inside(hit, *moved)
    if nearest is None:
        return None
    closest, bary = nearest
    if length(sub(hit, closest)) > radius * 1.02 + 1e-4:
        return None
    return toi, bary


class SweptSoftBodyVFTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.code = SPACE.read_text(encoding="utf-8")
        cls.header = HEADER.read_text(encoding="utf-8")
        cls.config = CONFIG.read_text(encoding="utf-8")
        cls.prediction = cls.code.split("static bool predict_soft_vertex_face_sweep(", 1)[1].split(
            "static void resolve_soft_soft_vertex_face_direction(", 1
        )[0]
        cls.solver = cls.code.split("static void resolve_soft_soft_vertex_face_direction(", 1)[1].split(
            "static void resolve_soft_soft_vertex_face_contacts(", 1
        )[0]
        cls.prestep = cls.code.split("void JoltSpace3D::_pre_step(float p_step) {", 1)[1].split(
            "void JoltSpace3D::_post_step(float p_step) {", 1
        )[0]

    def test_fast_tunneling_detected_before_current_overlap(self):
        tri = [(-1, 0, -1), (1, 0, -1), (0, 0, 1)]
        result = predict_sweep((0, .38, 0), (0, -35, 0), tri, [(0, 0, 0)] * 3, radius=.12)
        self.assertIsNotNone(result)
        toi, bary = result
        self.assertAlmostEqual(toi, (.38 - .12) / 35, places=8)
        self.assertTrue(all(x >= 0 for x in bary))
        self.assertAlmostEqual(sum(bary), 1.0)

    def test_both_triangle_windings_are_supported(self):
        tri = [(-1, 0, -1), (1, 0, -1), (0, 0, 1)]
        for winding in (tri, list(reversed(tri))):
            for side in (1, -1):
                result = predict_sweep((0, side * .55, 0), (0, -side * 45, 0),
                                       winding, [(0, 0, 0)] * 3, radius=.1)
                self.assertIsNotNone(result)

    def test_moving_plane_uses_relative_motion(self):
        tri = [(-1, 0, -1), (1, 0, -1), (0, 0, 1)]
        result = predict_sweep((0, .5, 0), (0, 0, 0), tri,
                               [(0, 40, 0)] * 3, radius=.1)
        self.assertIsNotNone(result)
        self.assertAlmostEqual(result[0], .01)
        # Translating with the point maintains distance and gives no TOI.
        self.assertIsNone(predict_sweep((0, .5, 0), (0, 40, 0),
                                        tri, [(0, 40, 0)] * 3))

    def test_misses_only_when_trajectory_is_outside_triangle(self):
        tri = [(-1, 0, -1), (1, 0, -1), (0, 0, 1)]
        self.assertIsNone(predict_sweep((3, .38, 0), (0, -35, 0), tri,
                                        [(0, 0, 0)] * 3, radius=.12))
        self.assertIsNone(predict_sweep((0, .38, 0), (0, 35, 0), tri,
                                        [(0, 0, 0)] * 3, radius=.12))

    def test_out_of_horizon_and_over_maximum_sweep_rejected(self):
        tri = [(-1, 0, -1), (1, 0, -1), (0, 0, 1)]
        zero_v = [(0, 0, 0)] * 3
        self.assertIsNone(predict_sweep((0, 2, 0), (0, -35, 0), tri, zero_v))
        self.assertIsNone(predict_sweep((0, .5, 0), (0, -200, 0), tri, zero_v,
                                        max_sweep=1))
        self.assertIsNotNone(predict_sweep((0, .5, 0), (0, -200, 0), tri, zero_v,
                                           max_sweep=4))

    def test_degeneracy_and_deforming_face_rejection(self):
        tri = [(-1, 0, -1), (1, 0, -1), (0, 0, 1)]
        self.assertIsNone(predict_sweep((0, .5, 0), (0, -35, 0),
                                        [(0, 0, 0)] * 3, [(0, 0, 0)] * 3))
        # The velocity field can translate/rotate individual vertices away
        # even if the mean suggests a hit. Verify the updated face is checked.
        shear = [(150, 0, 0), (150, 0, 0), (-300, 0, 0)]
        self.assertIsNone(predict_sweep((0, .5, 0), (0, -35, 0),
                                        tri, shear, radius=.1))

    def test_reference_momentum_and_predictive_speed_limit(self):
        incoming = -35
        effective_inverse_mass = 4.0
        correction = min(-incoming, 128)
        impulse = correction / effective_inverse_mass
        self.assertAlmostEqual(incoming + impulse * effective_inverse_mass, 0)
        self.assertGreater(-incoming, 8)  # Old discrete limit insufficient.
        self.assertLessEqual(correction, 128)

    def test_project_configuration_default_off_and_finite_clamps(self):
        self.assertIn("inline static bool soft_body_soft_speculative_ccd = false;", self.header)
        self.assertIn("inline static float soft_body_soft_ccd_max_sweep = 1.0f;", self.header)
        self.assertIn("inline static float soft_body_soft_ccd_max_correction_speed = 128.0f;", self.header)
        for item in ("soft_body_soft_speculative_ccd", "soft_body_soft_ccd_max_sweep",
                     "soft_body_soft_ccd_max_correction_speed"):
            self.assertIn('simulation/' + item, self.config)
        self.assertIn("Math::is_finite(ccd_sweep)", self.config)
        self.assertIn("Math::is_finite(ccd_correction)", self.config)
        self.assertIn("CLAMP(ccd_sweep, 0.0f, 4.0f)", self.config)

    def test_source_checks_swept_point_and_deformed_triangle(self):
        self.assertIn("face_cross", self.prediction)
        self.assertIn("relative_displacement_sq > p_max_sweep * p_max_sweep", self.prediction)
        self.assertIn("const float toi =", self.prediction)
        self.assertIn("toi < 0.0f || toi > p_step", self.prediction)
        self.assertIn("a_at_hit = p_a + p_va * toi", self.prediction)
        self.assertIn("b_at_hit = p_b + p_vb * toi", self.prediction)
        self.assertIn("c_at_hit = p_c + p_vc * toi", self.prediction)
        self.assertIn("closest_soft_triangle_point(point_at_hit,", self.prediction)
        self.assertIn("hit_tolerance", self.prediction)

    def test_source_gates_prediction_and_preserves_existing_solver(self):
        self.assertIn("JoltProjectSettings::soft_body_soft_speculative_ccd &&", self.solver)
        self.assertIn("if (distance_sq >= radius_sq)", self.solver)
        self.assertIn("if (!speculative_ccd || !predict_soft_vertex_face_sweep(", self.solver)
        self.assertIn("JoltProjectSettings::soft_body_soft_ccd_max_correction_speed", self.solver)
        self.assertIn("const float recovery_speed = swept_contact ? 0.0f", self.solver)
        self.assertIn("resolve_soft_soft_particle_contacts(*jolt_a, *jolt_b", self.prestep)
        self.assertIn("resolve_soft_soft_edge_edge_contacts(*jolt_a, *jolt_b", self.prestep)
        self.assertIn("broadphase_margin", self.prestep)
        self.assertIn("bounds_a.intersects(object_b->get_bounds().grow(broadphase_margin))", self.prestep)
        self.assertIn("candidate_radius", self.solver)
        self.assertIn("query_soft_face_bvh(", self.solver)

    def test_native_scene_uses_fast_body_with_masked_control_and_bvh(self):
        project = PROJECT.read_text(encoding="utf-8")
        fixture = FIXTURE.read_text(encoding="utf-8")
        self.assertIn("soft_body_soft_speculative_ccd=true", project)
        self.assertIn("soft_body_soft_vertex_face_bvh=true", project)
        self.assertIn("soft_body_soft_ccd_max_sweep=1.0", project)
        self.assertIn("const GRID := 8", fixture)
        self.assertIn("Vector3(0, -35.0, 0)", fixture)
        self.assertIn("masked_drop", fixture)
        self.assertIn("PASS: Jolt speculative swept soft vertex-face contact with masked control", fixture)


if __name__ == "__main__":
    unittest.main()
