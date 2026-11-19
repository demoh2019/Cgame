"""Analytical conservative rotational CCD broadphase bounds (2D and 3D).

A moving convex shape is contained within its initial world-space AABB.
Each AABB corner follows a sinusoidal coordinate trajectory as the body
rotates about its center of mass. Exact per-coordinate arc extrema + a
linear-motion envelope are conservative for every intermediate point.
The new path is opt-in; a CCD narrowphase TOI solver remains separate.
"""

import math
import random
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
HEADER = ROOT / "servers/physics_ccd_tight_rotational_bounds.h"
NATIVE = ROOT / "tests/servers/test_godot_physics_ccd_tight_rotational_bounds.cpp"
TAU = 2 * math.pi


def _in_angle(critical, start, span):
    distance = (critical - start) % TAU
    return distance <= span + 1e-6 or distance >= TAU - 1e-6


def arc_component(center, cosine, sine, angle):
    low = min(center + cosine, center + cosine * math.cos(angle) + sine * math.sin(angle))
    high = max(center + cosine, center + cosine * math.cos(angle) + sine * math.sin(angle))
    radius = math.hypot(cosine, sine)
    if abs(angle) >= TAU:
        return min(low, center - radius), max(high, center + radius)
    if radius:
        peak = math.atan2(sine, cosine)
        if _in_angle(peak, min(0, angle), abs(angle)):
            high = max(high, center + radius)
        if _in_angle(peak + math.pi, min(0, angle), abs(angle)):
            low = min(low, center - radius)
    return low, high


def cross(a, b):
    return (
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    )


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def envelope_2d(low, high, pivot, angle, motion):
    out_min, out_max = list(low), list(high)
    for mask in range(4):
        q = [low[i] if mask & (1 << i) else high[i] for i in range(2)]
        delta = [q[i] - pivot[i] for i in range(2)]
        segments = [
            arc_component(pivot[0], delta[0], -delta[1], angle),
            arc_component(pivot[1], delta[1], delta[0], angle),
        ]
        for i, (a, b) in enumerate(segments):
            out_min[i] = min(out_min[i], a)
            out_max[i] = max(out_max[i], b)
    for i in range(2):
        out_min[i] += min(0.0, motion[i])
        out_max[i] += max(0.0, motion[i])
    return out_min, out_max


def envelope_3d(low, high, pivot, axis, angle, motion):
    out_min, out_max = list(low), list(high)
    for mask in range(8):
        q = [low[i] if mask & (1 << i) else high[i] for i in range(3)]
        delta = [q[i] - pivot[i] for i in range(3)]
        parallel = [value * dot(axis, delta) for value in axis]
        perpendicular = [delta[i] - parallel[i] for i in range(3)]
        sine = cross(axis, delta)
        for i in range(3):
            a, b = arc_component(pivot[i] + parallel[i], perpendicular[i], sine[i], angle)
            out_min[i] = min(out_min[i], a)
            out_max[i] = max(out_max[i], b)
    for i in range(3):
        out_min[i] += min(0.0, motion[i])
        out_max[i] += max(0.0, motion[i])
    return out_min, out_max


def rotate_3d(point, axis, theta):
    cross_component = cross(axis, point)
    projection = dot(axis, point)
    return [
        value * math.cos(theta) + sine * math.sin(theta) +
        axis_component * projection * (1 - math.cos(theta))
        for value, sine, axis_component in zip(point, cross_component, axis)
    ]


def contained(point, low, high):
    return all(low[i] - 1e-9 <= point[i] <= high[i] + 1e-9 for i in range(len(point)))


class TightCCDRotationalBoundsContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.helper = HEADER.read_text(encoding="utf-8")
        cls.native = NATIVE.read_text(encoding="utf-8")

    def test_both_spaces_opt_in_with_legacy_default(self):
        for dim in ("2d", "3d"):
            with self.subTest(dim=dim):
                server = (ROOT / f"servers/physics_{dim}/physics_server_{dim}.cpp").read_text(encoding="utf-8")
                space_cpp = (ROOT / f"modules/godot_physics_{dim}/godot_space_{dim}.cpp").read_text(encoding="utf-8")
                space_h = (ROOT / f"modules/godot_physics_{dim}/godot_space_{dim}.h").read_text(encoding="utf-8")
                collision = (ROOT / f"modules/godot_physics_{dim}/godot_collision_object_{dim}.cpp").read_text(encoding="utf-8")
                self.assertIn(f'"physics/{dim}/solver/ccd_tight_rotational_bounds"), false);', server)
                self.assertIn(f'GLOBAL_GET("physics/{dim}/solver/ccd_tight_rotational_bounds")', space_cpp)
                self.assertIn("bool ccd_tight_rotational_bounds = false;", space_h)
                self.assertIn("is_ccd_tight_rotational_bounds_enabled() const", space_h)
                self.assertIn("is_ccd_tight_rotational_bounds_enabled()", collision)
                self.assertIn("rotation_factor > real_t(0.0)", collision)
                self.assertIn("godot_physics_ccd_rotational_padding(", collision)

    def test_math_preserves_rotation_sense_and_corner_extrema(self):
        self.assertIn("Math::atan2(p_sin_coefficient, p_cos_coefficient)", self.helper)
        self.assertIn("Math::fposmod(", self.helper)
        self.assertIn("p_span >= full_turn", self.helper)
        self.assertIn("sine_coefficient = axis.cross(delta)", self.helper)
        self.assertIn("perpendicular = delta - parallel", self.helper)
        self.assertIn("const Vector3 axis = p_angular_step / angle;", self.helper)

    def test_native_checks_both_dimensions(self):
        self.assertIn("TEST_FORCE_LINK(test_godot_physics_ccd_tight_rotational_bounds)", self.native)
        self.assertEqual(self.native.count("TEST_CASE("), 4)

    def test_zero_rotation_is_linear_sweep_only(self):
        lo2, hi2 = envelope_2d((2, -1), (5, 3), (0, 0), 0, (4, -3))
        self.assertEqual(lo2, [2, -4])
        self.assertEqual(hi2, [9, 3])

    def test_random_2d_arcs_include_every_sampled_corner(self):
        rng = random.Random(16012)
        for _ in range(900):
            low = [rng.uniform(-10, 10) for _ in range(2)]
            high = [x + rng.uniform(.05, 5) for x in low]
            pivot = [rng.uniform(-7.5, 7.5) for _ in range(2)]
            motion = [rng.uniform(-1.5, 1.5) for _ in range(2)]
            angle = rng.uniform(-3.6 * math.pi, 3.6 * math.pi)
            bounded_low, bounded_high = envelope_2d(low, high, pivot, angle, motion)
            for mask in range(4):
                q = [low[i] if mask & (1 << i) else high[i] for i in range(2)]
                dx, dy = [q[i] - pivot[i] for i in range(2)]
                for i in range(21):
                    t = i / 20
                    c, s = math.cos(t * angle), math.sin(t * angle)
                    point = (pivot[0] + c * dx - s * dy + motion[0] * t,
                             pivot[1] + s * dx + c * dy + motion[1] * t)
                    self.assertTrue(contained(point, bounded_low, bounded_high))

    def test_random_3d_arcs_include_every_sampled_corner(self):
        rng = random.Random(16013)
        for _ in range(900):
            low = [rng.uniform(-10, 10) for _ in range(3)]
            high = [x + rng.uniform(.05, 5) for x in low]
            pivot = [rng.uniform(-7.5, 7.5) for _ in range(3)]
            motion = [rng.uniform(-1.5, 1.5) for _ in range(3)]
            v = [rng.uniform(-1, 1) for _ in range(3)]
            length = math.sqrt(dot(v, v))
            axis = [x / length for x in v]
            angle = rng.uniform(0.001, 3.6 * math.pi)
            bounded_low, bounded_high = envelope_3d(low, high, pivot, axis, angle, motion)
            for mask in range(8):
                q = [low[i] if mask & (1 << i) else high[i] for i in range(3)]
                delta = [q[i] - pivot[i] for i in range(3)]
                for i in range(21):
                    t = i / 20
                    rotated = rotate_3d(delta, axis, angle * t)
                    point = [pivot[i] + rotated[i] + motion[i] * t for i in range(3)]
                    self.assertTrue(contained(point, bounded_low, bounded_high))

    def test_long_thin_rotating_boxes_reduce_swept_proxy_volume(self):
        bounds2 = envelope_2d((8, -1), (12, 1), (0, 0), .4, (0, 0))
        radius2 = math.hypot(12, 1)
        padding2 = radius2 * 2 * math.sin(.4 / 2)
        old2 = (4 + 2 * padding2) * (2 + 2 * padding2)
        new2 = math.prod(high - low for low, high in zip(*bounds2))
        self.assertLess(new2, old2 * .5)

        bounds3 = envelope_3d((8, -1, -2), (12, 1, 2), (0, 0, 0), (0, 0, 1), .4, (0, 0, 0))
        radius3 = math.sqrt(12 ** 2 + 1 + 2 ** 2)
        padding3 = radius3 * 2 * math.sin(.4 / 2)
        old3 = (4 + 2 * padding3) * (2 + 2 * padding3) * (4 + 2 * padding3)
        new3 = math.prod(high - low for low, high in zip(*bounds3))
        self.assertLess(new3, old3 * .5)


if __name__ == "__main__":
    unittest.main()
