"""SoftBody3D finite segment-cast, backface, face-index regression contracts.

Run:
    python3 -m unittest discover -s tests/stress -p test_physics_soft_segment_raycast.py -v

These tests check source integration plus an independent numerical reference
model. Native behavior requires physics_soft_segment_raycast_regression.gd.
"""
from math import isclose
from pathlib import Path
import unittest


SOURCE = Path(__file__).resolve().parents[2] / "modules/godot_physics_3d/godot_soft_body_3d.cpp"

UP_TRIANGLE = ((-1.0, 0.0, -1.0), (0.0, 0.0, 1.0), (1.0, 0.0, -1.0))


def subtract(a, b):
    return tuple(x - y for x, y in zip(a, b))


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1],
            a[2] * b[0] - a[0] * b[2],
            a[0] * b[1] - a[1] * b[0])


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def reference_triangle_segment(start, end, points, back_faces):
    """Independent Moller-Trumbore finite-segment reference."""
    a, b, c = points
    ray = subtract(end, start)
    e1, e2 = subtract(b, a), subtract(c, a)
    p = cross(ray, e2)
    determinant = dot(e1, p)
    if abs(determinant) < 1e-10:
        return None
    reciprocal = 1.0 / determinant
    tvec = subtract(start, a)
    u = dot(tvec, p) * reciprocal
    if u < 0.0 or u > 1.0:
        return None
    qvec = cross(tvec, e1)
    v = dot(ray, qvec) * reciprocal
    if v < 0.0 or u + v > 1.0:
        return None
    fraction = dot(e2, qvec) * reciprocal
    max_component = max(abs(component) for component in ray)
    if max_component <= 1e-5 or not (1e-5 / max_component < fraction <= 1.0):
        return None
    normal = cross(e1, e2)
    back_face = dot(normal, ray) > 0
    if back_face and not back_faces:
        return None
    position = tuple(start[i] + ray[i] * fraction for i in range(3))
    return fraction, position, back_face


class SoftBodySegmentRaycastContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source = SOURCE.read_text(encoding="utf-8")
        begin = source.index("struct _SoftBodyIntersectSegmentInfo {")
        end = source.index("bool GodotSoftBodyShape3D::intersect_point(", begin)
        cls.cast = source[begin:end]

    def test_bounded_triangle_intersection_replaces_infinite_ray(self):
        code = self.cast
        self.assertIn("const real_t fraction = e2.dot(q) * inverse_determinant;", code)
        self.assertIn("fraction <= 1.0", code)
        self.assertNotIn("Geometry3D::ray_intersects_triangle(query_info.from", code)
        self.assertIn("if (!(max_component > CMP_EPSILON))", code)

    def test_respects_backface_policy_and_orients_hit_normal(self):
        code = self.cast
        self.assertIn("const bool back_face = determinant < 0.0;", code)
        self.assertIn("if (back_face && !query_info.hit_back_faces)", code)
        self.assertIn("query_info.hit_normal = back_face ? -normal : normal;", code)
        self.assertIn("query_info.hit_back_faces = p_hit_back_faces;", code)

    def test_propagates_selected_face_index_and_normal(self):
        code = self.cast
        self.assertIn("r_face_index = int(query_info.hit_face_index);", code)
        self.assertIn("r_normal = query_info.hit_normal;", code)
        self.assertIn("uint32_t hit_face_index = UINT32_MAX;", code)

    def test_nearest_hit_avoids_squared_distance_overflow(self):
        code = self.cast
        self.assertIn("const real_t fraction = e2.dot(q) * inverse_determinant;", code)
        self.assertIn("fraction >= query_info.closest_fraction", code)
        self.assertIn("query_info.closest_fraction = fraction;", code)
        self.assertIn("query_info.minimum_fraction = CMP_EPSILON / max_component;", code)
        self.assertNotIn("hit_dist_sq", code)
        self.assertNotIn("distance_squared_to(result)", code)

    def test_rejects_hits_just_past_segment_endpoint(self):
        self.assertIsNone(reference_triangle_segment(
            (0.0, 1.0, 0.0), (0.0, 0.025, 0.0), UP_TRIANGLE, False))
        hit = reference_triangle_segment(
            (0.0, 1.0, 0.0), (0.0, -0.25, 0.0), UP_TRIANGLE, False)
        self.assertIsNotNone(hit)
        self.assertTrue(isclose(hit[1][1], 0.0))

    def test_backfaces_off_by_default_and_reversed_when_enabled(self):
        start, end = (0, -1, 0), (0, 1, 0)
        self.assertIsNone(reference_triangle_segment(start, end, UP_TRIANGLE, False))
        hit = reference_triangle_segment(start, end, UP_TRIANGLE, True)
        self.assertIsNotNone(hit)
        self.assertTrue(hit[2])

    def test_nearest_of_multiple_intersections(self):
        lower = tuple((x, y - 0.5, z) for x, y, z in UP_TRIANGLE)
        start, end = (0, 1, 0), (0, -1, 0)
        hits = [(face, reference_triangle_segment(start, end, triangle, False))
                for face, triangle in enumerate((UP_TRIANGLE, lower))]
        ordered = sorted((hit[1][0], hit[0]) for hit in hits if hit[1] is not None)
        self.assertEqual(ordered[0][1], 0)
        self.assertLess(ordered[0][0], ordered[1][0])

    def test_long_ray_still_hits_just_after_start(self):
        # A fixed fraction epsilon drops this valid hit at t~=1e-8.
        hit = reference_triangle_segment(
            (0.0, 1.0, 0.0), (0.0, -1e8, 0.0), UP_TRIANGLE, False)
        self.assertIsNotNone(hit)
        self.assertLess(hit[0], 1e-6)
        self.assertAlmostEqual(hit[1][1], 0.0)

    def test_long_segment_fraction_avoids_float32_squared_overflow(self):
        start = (0.0, 1e20, 0.0)
        end = (0.0, -1e20, 0.0)
        point = (0.0, 0.0, 0.0)
        fraction = (point[1] - start[1]) / (end[1] - start[1])
        self.assertAlmostEqual(fraction, 0.5)
        self.assertGreater(1e20 * 1e20, 3.4028235e38)


if __name__ == "__main__":
    unittest.main()
