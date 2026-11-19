"""Numerical and source regressions for scale-invariant XPBD vertex-face projection.

Run:
 python3 -m unittest discover -s tests/stress -p test_physics_xpbd_self_collision_scale.py -v

Native regression:
 ./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test --test-case="[PhysicsSelfCollisionScale]"
"""
import math
import random
import struct
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


def f32(value):
    return struct.unpack("<f", struct.pack("<f", value))[0]


def reference_projection(point, a, b, c):
    """Independent numerical reference using double intermediate operations."""
    edge_a = [float(b[i]) - float(a[i]) for i in range(3)]
    edge_b = [float(c[i]) - float(a[i]) for i in range(3)]
    rel = [float(point[i]) - float(a[i]) for i in range(3)]
    normal = (
        edge_a[1] * edge_b[2] - edge_a[2] * edge_b[1],
        edge_a[2] * edge_b[0] - edge_a[0] * edge_b[2],
        edge_a[0] * edge_b[1] - edge_a[1] * edge_b[0],
    )
    nn = sum(x * x for x in normal)
    d00 = sum(x * x for x in edge_a)
    d11 = sum(x * x for x in edge_b)
    scale_sq = d00 * d11
    if not (math.isfinite(nn) and math.isfinite(scale_sq)
            and scale_sq > 0 and nn > scale_sq * 1e-20):
        return None
    unit = tuple(x / math.sqrt(nn) for x in normal)
    distance = sum(x * y for x, y in zip(rel, unit))
    d01 = sum(x * y for x, y in zip(edge_a, edge_b))
    d20 = sum(x * y for x, y in zip(rel, edge_a))
    d21 = sum(x * y for x, y in zip(rel, edge_b))
    v = (d11 * d20 - d01 * d21) / nn
    w = (d00 * d21 - d01 * d20) / nn
    u = 1 - v - w
    if not all(math.isfinite(x) for x in (u, v, w)):
        return None
    if not all(0 <= x <= 1 for x in (u, v, w)):
        return None
    return unit, (u, v, w), distance


class XPBDSelfCollisionScale(unittest.TestCase):
    def test_big_float32_triangle_no_cross_overflow(self):
        scale = f32(1e20)
        r = reference_projection((f32(scale / 4), f32(scale / 4), f32(scale / 100)),
                                 (0, 0, 0), (scale, 0, 0), (0, scale, 0))
        self.assertIsNotNone(r)
        normal, bary, distance = r
        self.assertAlmostEqual(normal[2], 1)
        self.assertAlmostEqual(bary[0], 0.5, places=5)
        self.assertAlmostEqual(distance / scale, 0.01, places=5)

    def test_small_float32_triangle_no_fixed_epsilon(self):
        scale = f32(1e-8)
        r = reference_projection((f32(scale / 4), f32(scale / 4), f32(scale / 10)),
                                 (0, 0, 0), (scale, 0, 0), (0, scale, 0))
        self.assertIsNotNone(r)
        normal, bary, distance = r
        self.assertAlmostEqual(normal[2], 1.0)
        self.assertAlmostEqual(bary[1], 0.25, places=5)
        self.assertAlmostEqual(distance / scale, 0.1, places=5)

    def test_randomized_float32_scales(self):
        rng = random.Random(20261119)
        for _ in range(4000):
            scale = f32(10 ** rng.uniform(-20, 22))
            u = rng.uniform(0.08, 0.45)
            v = rng.uniform(0.08, 0.45)
            point = (f32(u * scale), f32(v * scale), f32(0.01 * scale))
            result = reference_projection(point, (0, 0, 0),
                                         (scale, 0, 0), (0, scale, 0))
            self.assertIsNotNone(result)
            self.assertAlmostEqual(result[1][1], u, delta=2e-6)
            self.assertAlmostEqual(result[1][2], v, delta=2e-6)

    def test_reversed_winding_and_nearly_collinear(self):
        r = reference_projection((0.2, 0.3, 0.1), (0, 0, 0),
                                 (0, 1, 0), (1, 0, 0))
        self.assertIsNotNone(r)
        self.assertLess(r[0][2], 0)
        self.assertAlmostEqual(r[2], -0.1)
        self.assertIsNone(reference_projection((0.5, 0, 0), (0, 0, 0),
                                                (1, 0, 0), (2, 1e-12, 0)))

    def test_wide_math_in_source_and_atomic_outputs(self):
        source = (ROOT / "servers/physics_xpbd_self_collision.h").read_text()
        self.assertIn("double(p_b.x) - double(p_a.x)", source)
        self.assertIn("const double normal_squared =", source)
        self.assertIn("normal_squared > scale_squared * 1.0e-20", source)
        self.assertIn("const double v = (d11 * d20 - d01 * d21) / normal_squared;", source)
        self.assertNotIn("const Vector3 normal = ab.cross(ac);", source)
        self.assertNotIn("CMP_EPSILON * CMP_EPSILON", source)
        self.assertLess(source.index("if (!normal.is_finite() || !barycentric.is_finite()"),
                        source.index("r_normal = normal;"))

    def test_existing_normal_and_tangent_solves_both_use_projection(self):
        normal = (ROOT / "servers/physics_xpbd_self_collision.h").read_text()
        tangent = (ROOT / "servers/physics_xpbd_self_friction.h").read_text()
        self.assertGreaterEqual(normal.count("physics_xpbd_self_collision_face_projection("), 2)
        self.assertIn("physics_xpbd_self_collision_face_projection(", tangent)
        native = (ROOT / "tests/servers/test_physics_xpbd_self_collision_scale.cpp").read_text()
        self.assertEqual(native.count('TEST_CASE("[PhysicsSelfCollisionScale]'), 6)


if __name__ == "__main__":
    unittest.main()
