"""XPBD extreme-scale numerical and source contracts.

Run from repository root:
  python3 -m unittest discover -s tests/stress -p test_physics_xpbd_extreme_scale.py -v

The native tests are in tests/servers/test_physics_xpbd_extreme_scale.cpp.
"""
import math
from pathlib import Path
import struct
import unittest

ROOT = Path(__file__).resolve().parents[2]


def f32(value):
    try:
        return struct.unpack("<f", struct.pack("<f", value))[0]
    except OverflowError:
        return math.copysign(math.inf, value)


def project(a, b, rest, w_a, w_b, alpha=0.0, old_lambda=0.0):
    # Independent wide-intermediate reference for a 1D XPBD link.
    distance = float(b) - float(a)
    norm = abs(distance)
    if norm == 0 or w_a + w_b == 0:
        return (a, b, old_lambda, False)
    dl = (rest - norm - alpha * old_lambda) / (w_a + w_b + alpha)
    new_lambda = f32(old_lambda + dl)
    if not math.isfinite(new_lambda):
        return (a, b, old_lambda, False)
    direction = math.copysign(1.0, distance)
    return (f32(a - w_a * direction * dl), f32(b + w_b * direction * dl), new_lambda, True)


class XPBDExtremeScaleContracts(unittest.TestCase):
    def test_large_finite_link_overflowed_float32_squared_length(self):
        length = f32(2e20)
        self.assertTrue(math.isfinite(length))
        self.assertFalse(math.isfinite(f32(length * length)))
        a, b, lam, ok = project(0.0, length, f32(1e20), 1.0, 1.0)
        self.assertTrue(ok)
        self.assertAlmostEqual(a / 1e20, 0.5, places=5)
        self.assertAlmostEqual(b / 1e20, 1.5, places=5)

    def test_tiny_link_below_legacy_epsilon(self):
        a, b, _, ok = project(0.0, f32(2e-8), f32(1e-8), 1.0, 1.0)
        self.assertTrue(ok)
        self.assertAlmostEqual(a / 1e-8, 0.5, places=5)
        self.assertAlmostEqual(b / 1e-8, 1.5, places=5)

    def test_multiplier_overflow_is_transactional(self):
        a, b, lam, ok = project(0.0, f32(1e20), 0.0, f32(1e-20), f32(1e-20))
        self.assertFalse(ok)
        self.assertEqual((a, b, lam), (0.0, f32(1e20), 0.0))

    def test_shared_xpbd_kernel_uses_double_intermediates(self):
        src = (ROOT / "servers/physics_xpbd_distance.h").read_text()
        self.assertIn("double(r_b.x) - double(r_a.x)", src)
        self.assertIn("double(r_b.y) - double(r_a.y)", src)
        self.assertIn("const double distance_squared", src)
        self.assertIn("const real_t next_lambda = real_t(next_lambda_double);", src)
        self.assertIn("if (!next_a.is_finite() || !next_b.is_finite())", src)
        self.assertNotIn("delta.length_squared()", src)

    def test_no_unexpected_rigid_fallback_for_small_timestep(self):
        src = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.cpp").read_text()
        self.assertIn("alpha = real_t(MIN(alpha_double, double(std::numeric_limits<real_t>::max())))", src)
        self.assertNotIn("alpha_double <= double(std::numeric_limits<real_t>::max())", src)

    def test_new_native_tests_present(self):
        src = (ROOT / "tests/servers/test_physics_xpbd_extreme_scale.cpp").read_text()
        self.assertIn("TEST_FORCE_LINK(test_physics_xpbd_extreme_scale)", src)
        self.assertEqual(src.count('TEST_CASE("[PhysicsXPBD]'), 4)


if __name__ == "__main__":
    unittest.main()
