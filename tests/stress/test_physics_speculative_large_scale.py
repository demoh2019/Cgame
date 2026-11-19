"""Source and numeric regression checks for overflow-safe speculative sphere CCD.

Native 2D/3D execution is covered separately by the PhysicsSpeculative doctests.
"""

import math
from pathlib import Path
import struct
import unittest


ROOT = Path(__file__).resolve().parents[2]


def f32(value):
    """Round to float32, including overflow-to-infinity semantics."""
    try:
        return struct.unpack("<f", struct.pack("<f", value))[0]
    except OverflowError:
        return math.copysign(math.inf, value)


class PhysicsSpeculativeLargeScaleTests(unittest.TestCase):
    def test_large_finite_distance_no_longer_requires_float32_squared_length(self):
        distance = f32(2.5e19)
        self.assertTrue(math.isfinite(distance))
        self.assertTrue(math.isinf(f32(distance * distance)))
        self.assertTrue(math.isfinite(math.sqrt(float(distance) * distance)))
        self.assertAlmostEqual(math.sqrt(float(distance) * distance) / distance, 1.0)

    def test_opposing_velocities_can_have_representable_displacement(self):
        speed = f32(2e38)
        step = f32(1e-19)
        self.assertTrue(math.isfinite(speed))
        self.assertTrue(math.isinf(f32(speed - (-speed))))
        displacement = f32(f32(speed * step) - f32(-speed * step))
        self.assertTrue(math.isfinite(displacement))
        self.assertGreater(displacement, f32(5e18))

    def test_shared_helper_uses_wide_fallback_without_allocations(self):
        source = (ROOT / "servers/physics_speculative_sphere_contact.h").read_text()
        self.assertIn("physics_speculative_sphere_length_squared_wide(const Vector2", source)
        self.assertIn("physics_speculative_sphere_length_squared_wide(const Vector3", source)
        self.assertIn("physics_speculative_sphere_normal_wide(const Vector2", source)
        self.assertIn("physics_speculative_sphere_normal_wide(const Vector3", source)
        self.assertIn("if (Math::is_finite(distance_squared) && distance_squared > real_t(0.0))", source)
        self.assertIn("relative_motion = p_velocity_a * p_step - p_velocity_b * p_step;", source)
        self.assertIn("double(p_radius_a) + double(p_radius_b)", source)

    def test_native_2d_and_3d_regressions_are_present(self):
        source = (ROOT / "tests/servers/test_physics_speculative_sphere_contact.cpp").read_text()
        self.assertIn("large finite separations keep predictive 2D and 3D contacts", source)
        self.assertIn("overflowed relative speed can have finite short-step displacement", source)
        self.assertIn("CHECK_FALSE(physics_speculative_sphere_contact(", source)


if __name__ == "__main__":
    unittest.main()
