"""Numerical and source-wiring checks for opt-in XPBD soft-body fibers."""
from __future__ import annotations
import math
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]

def fiber_alpha(a, b, alpha, axis, ratio):
    """Independent double-precision numerical oracle for C++ fiber projection."""
    if alpha < 0 or not math.isfinite(alpha):
        return 0.0
    if (alpha == 0 or ratio == 1 or axis not in (0, 1, 2)
            or ratio <= 0 or not math.isfinite(ratio)
            or not all(math.isfinite(v) for v in (*a, *b))):
        return alpha
    d = [b[i] - a[i] for i in range(3)]
    scale = max(map(abs, d))
    if not math.isfinite(scale) or scale <= 0:
        return alpha
    scaled = [v / scale for v in d]
    projection = scaled[axis] ** 2 / sum(v * v for v in scaled)
    return alpha * (1 + (ratio - 1) * projection)

class XPBDFiberTests(unittest.TestCase):
    def test_warp_weft_and_diagonal(self):
        a = (0, 0, 0)
        self.assertAlmostEqual(fiber_alpha(a, (1, 0, 0), .1, 0, 4), .4)
        self.assertAlmostEqual(fiber_alpha(a, (0, 1, 0), .1, 0, 4), .1)
        self.assertAlmostEqual(fiber_alpha(a, (1, 1, 0), .1, 0, 4), .25)
        self.assertAlmostEqual(fiber_alpha(a, (0, 0, 5), .1, 2, .25), .025)

    def test_zero_and_invalid(self):
        self.assertEqual(fiber_alpha((0, 0, 0), (0, 0, 0), .1, 0, 4), .1)
        self.assertEqual(fiber_alpha((0, 0, 0), (1, 0, 0), .1, 0, 1), .1)
        self.assertEqual(fiber_alpha((0, 0, 0), (1, 0, 0), 0, 0, 4), 0)
        self.assertEqual(fiber_alpha((0, 0, 0), (1, 0, 0), .1, 99, 4), .1)
        self.assertEqual(fiber_alpha((0, 0, 0), (1, 0, 0), .1, 0, float('nan')), .1)
        self.assertEqual(fiber_alpha((0, 0, 0), (1, 0, 0), float('inf'), 0, 4), 0)

    def test_reverse_translation_and_extreme_scale(self):
        for scale in (1e-12, 1e20):
            a, b = (0, 0, 0), (scale, scale, 0)
            self.assertAlmostEqual(fiber_alpha(a, b, .1, 0, 4), .25)
            self.assertAlmostEqual(fiber_alpha(b, a, .1, 0, 4), .25)
        self.assertAlmostEqual(
            fiber_alpha((100, 100, 3), (101, 101, 3), .1, 0, 4), .25
        )

    def test_compatibility_and_wiring(self):
        server = (ROOT / "servers/physics_3d/physics_server_3d.cpp").read_text()
        space_h = (ROOT / "modules/godot_physics_3d/godot_space_3d.h").read_text()
        space_cpp = (ROOT / "modules/godot_physics_3d/godot_space_3d.cpp").read_text()
        body_h = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.h").read_text()
        body_cpp = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.cpp").read_text()
        helper = (ROOT / "servers/physics_xpbd_fiber.h").read_text()
        self.assertIn('"physics/3d/solver/soft_body_xpbd_fiber_axis", PROPERTY_HINT_ENUM, "Disabled,X,Y,Z"), 0', server)
        self.assertIn('"physics/3d/solver/soft_body_xpbd_fiber_compliance_ratio", PROPERTY_HINT_RANGE, "0.1,10,0.05"), 1.0', server)
        self.assertIn("get_soft_body_xpbd_fiber_axis()", space_h)
        self.assertIn("get_soft_body_xpbd_fiber_compliance_ratio()", space_h)
        self.assertIn("Math::is_finite(configured_fiber_ratio)", space_cpp)
        self.assertIn("LocalVector<real_t> xpbd_fiber_alphas", body_h)
        self.assertIn('servers/physics_xpbd_fiber.h', body_cpp)
        self.assertIn("physics_xpbd_fiber_alpha(", body_cpp)
        self.assertIn("link.n[0]->s, link.n[1]->s", body_cpp)
        self.assertIn("use_fiber_xpbd ? xpbd_fiber_alphas[link_index] : alpha", body_cpp)
        self.assertIn("xpbd_fiber_alphas.reset();", body_cpp)
        self.assertIn("Math::is_finite(result)", helper)
        self.assertIn("std::numeric_limits<real_t>::max()", helper)

    def test_native_regressions_registered(self):
        content = (ROOT / "tests/servers/test_physics_xpbd_fiber.cpp").read_text()
        self.assertIn("TEST_FORCE_LINK(test_physics_xpbd_fiber)", content)
        self.assertGreaterEqual(content.count('TEST_CASE('), 6)

if __name__ == "__main__":
    unittest.main()
