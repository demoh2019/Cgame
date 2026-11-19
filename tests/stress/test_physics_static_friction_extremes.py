"""Numerical and source contracts for float32-safe 3D Coulomb friction.

Run: python3 -m unittest tests.stress.test_physics_static_friction_extremes
Native physics verification requires a tests=yes Cgame build.
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


def clamp_wide(vec, dynamic_limit, static_multiplier):
    largest = max(abs(component) for component in vec)
    if largest == 0:
        return (0.0, 0.0, 0.0)
    normalized = [component / largest for component in vec]
    unit_length = math.sqrt(sum(component * component for component in normalized))
    static_limit = max(dynamic_limit, 0.0) * max(static_multiplier, 1.0)
    if largest <= static_limit / unit_length:
        return tuple(vec)
    projected = max(dynamic_limit, 0.0) / unit_length
    return tuple(component * projected for component in normalized)


class StaticFrictionExtremeContracts(unittest.TestCase):
    def test_finite_float32_vector_can_have_overflowed_squared_length(self):
        x = f32(1e20)
        self.assertTrue(math.isfinite(x))
        self.assertTrue(math.isinf(f32(f32(x * x) + f32(x * x))))
        projected = clamp_wide((x, -x, 0.0), 5.0, 2.0)
        self.assertAlmostEqual(math.hypot(*projected), 5.0, places=6)
        self.assertGreater(projected[0], 0.0)
        self.assertLess(projected[1], 0.0)

    def test_large_static_cone_retains_candidate(self):
        vector = (f32(1e20), f32(-1e20), 0.0)
        self.assertEqual(clamp_wide(vector, f32(1e20), 2.0), vector)

    def test_small_friction_limit_is_not_lost_by_float32_scale_underflow(self):
        vector = (f32(1e38), f32(-1e38), 0.0)
        # A single float32 ratio underflows even though each output component is representable.
        ratio = f32(1e-10 / math.hypot(*vector))
        self.assertEqual(ratio, 0.0)
        projected = clamp_wide(vector, f32(1e-10), 1.0)
        self.assertNotEqual(f32(projected[0]), 0.0)
        self.assertAlmostEqual(projected[0] / 1e-10, math.sqrt(0.5), places=5)

    def test_shared_solver_wiring_and_native_regressions(self):
        header = (ROOT / "servers/physics_contact_static_friction.h").read_text()
        self.assertIn("Math::is_finite(candidate_length_squared)", header)
        self.assertIn("Math::is_finite(static_limit_squared)", header)
        self.assertIn("double(p_candidate.x)", header)
        self.assertIn("return Vector3(real_t(nx * projected)", header)
        source3d = (ROOT / "modules/godot_physics_3d/godot_body_pair_3d.cpp").read_text()
        self.assertEqual(source3d.count("godot_physics_clamp_static_friction_3d("), 2)
        native = (ROOT / "tests/servers/test_godot_physics_contact_static_friction.cpp").read_text()
        self.assertIn('3D large finite slip keeps a nonzero kinetic friction impulse', native)
        self.assertIn('3D large finite impulse stays inside large static cone', native)
        self.assertIn('3D large impulse and tiny kinetic limit do not underflow scale', native)


if __name__ == "__main__":
    unittest.main()
