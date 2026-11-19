"""Numerical and source contracts for scale-robust XPBD cloth edge/edge collisions.

Run:
    python3 -m unittest discover -s tests/stress -p test_physics_xpbd_edge_scale.py -v

The native C++ tests are in tests/servers/test_physics_xpbd_edge_scale.cpp.
"""
import math
import random
import struct
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def f32(x):
    return struct.unpack("<f", struct.pack("<f", x))[0]


def closest_edges(a, b, c, d):
    """Independent wide-intermediate reference, with interior-only contacts."""
    ab = tuple(b[i] - a[i] for i in range(3))
    cd = tuple(d[i] - c[i] for i in range(3))
    rr = tuple(a[i] - c[i] for i in range(3))
    dot = lambda u, v: sum(x * y for x, y in zip(u, v))
    cross = (ab[1] * cd[2] - ab[2] * cd[1],
             ab[2] * cd[0] - ab[0] * cd[2],
             ab[0] * cd[1] - ab[1] * cd[0])
    aa, bb, cc = dot(ab, ab), dot(ab, cd), dot(cd, cd)
    dd, ee = dot(ab, rr), dot(cd, rr)
    denominator = dot(cross, cross)
    if not aa > 0 or not cc > 0 or not math.isfinite(denominator):
        return None
    if denominator <= 1e-5 * aa * cc:
        return None
    s = (bb * ee - cc * dd) / denominator
    t = (aa * ee - bb * dd) / denominator
    if not (0.001 < s < 0.999 and 0.001 < t < 0.999):
        return None
    separation = tuple((a[i] + ab[i] * s) - (c[i] + cd[i] * t) for i in range(3))
    sq = dot(separation, separation)
    direction = separation if sq > max(aa, cc) * 1e-24 else cross
    invlength = 1 / math.sqrt(dot(direction, direction))
    return (s, t, math.sqrt(sq), tuple(x * invlength for x in direction))


class EdgeEdgeScaleContracts(unittest.TestCase):
    def test_large_and_tiny_float32_edges(self):
        for scale in (f32(1e-20), f32(1e-8), 1.0, f32(1e20)):
            a, b = (-scale, 0, 0), (scale, 0, 0)
            c, d = (0, -scale, f32(scale * 0.1)), (0, scale, f32(scale * 0.1))
            result = closest_edges(a, b, c, d)
            self.assertIsNotNone(result)
            s, t, dist, normal = result
            self.assertAlmostEqual(s, 0.5, places=6)
            self.assertAlmostEqual(t, 0.5, places=6)
            self.assertAlmostEqual(dist / scale, 0.1, places=5)
            self.assertAlmostEqual(normal[2], -1.0, places=6)

    def test_crossed_edges_fallback_normal(self):
        result = closest_edges((-1, 0, 0), (1, 0, 0),
                               (0, -1, 0), (0, 1, 0))
        self.assertIsNotNone(result)
        self.assertEqual(result[2], 0)
        self.assertAlmostEqual(result[3][2], 1, places=7)

    def test_parallel_and_endpoints_are_not_interior_edge_contacts(self):
        self.assertIsNone(closest_edges((0, 0, 0), (1, 0, 0),
                                        (0, 1, 0), (1, 1, 0)))
        self.assertIsNone(closest_edges((-1, 0, 0), (1, 0, 0),
                                        (1, -1, 0), (1, 1, 0)))

    def test_randomized_interior_pairs_over_extreme_scales(self):
        rng = random.Random(20261119)
        accepted = 0
        for _ in range(10000):
            scale = f32(10 ** rng.uniform(-19, 23))
            s = rng.uniform(0.05, 0.95)
            t = rng.uniform(0.05, 0.95)
            gap = f32(scale * 0.25)
            a, b = (0.0, 0.0, 0.0), (scale, 0.0, 0.0)
            c = (f32(s * scale), f32(-t * scale), gap)
            d = (c[0], f32((1 - t) * scale), gap)
            result = closest_edges(a, b, c, d)
            self.assertIsNotNone(result)
            self.assertAlmostEqual(result[0], c[0] / scale, places=5)
            self.assertAlmostEqual(result[1],
                                   -c[1] / (d[1] - c[1]), places=5)
            self.assertAlmostEqual(result[2] / scale, 0.25, places=5)
            accepted += 1
        self.assertEqual(accepted, 10000)

    def test_source_uses_wide_math_before_products(self):
        src = (ROOT / "servers/physics_xpbd_edge_collision.h").read_text()
        narrow = src.split("_FORCE_INLINE_ bool physics_xpbd_closest_edges(", 1)[1].split(
            "// One unilateral XPBD edge/edge distance row.", 1)[0]
        self.assertIn("double(p_b.x) - double(p_a.x)", narrow)
        self.assertIn("const double cross_squared =", narrow)
        self.assertIn("cross_squared > double(CMP_EPSILON) * edge_scale", narrow)
        self.assertIn("const double distance_squared = dx * dx", narrow)
        self.assertNotIn("const Vector3 ab = p_b - p_a;", narrow)
        self.assertNotIn("aa * cc - bb * bb", narrow.split("if (!(aa > 0.0)", 1)[1])
        self.assertIn("const Vector3 next_normal{ real_t(nx), real_t(ny), real_t(nz) };", narrow)
        self.assertLess(narrow.index("if (!next_normal.is_finite()"),
                        narrow.index("r_s = real_t(s);"))

    def test_existing_xpbd_edge_collision_reuses_wide_narrowphase(self):
        src = (ROOT / "servers/physics_xpbd_edge_collision.h").read_text()
        self.assertGreaterEqual(src.count("physics_xpbd_closest_edges("), 2)
        self.assertIn("physics_xpbd_solve_edge_collision(", src)
        native = (ROOT / "tests/servers/test_physics_xpbd_edge_scale.cpp").read_text()
        self.assertEqual(native.count('TEST_CASE("[PhysicsEdgeScale]'), 7)


if __name__ == "__main__":
    unittest.main()
