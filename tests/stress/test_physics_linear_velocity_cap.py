"""Contracts for Rapier-style 2D/3D maximum dynamic linear speed."""

from pathlib import Path
import math
import unittest

ROOT = Path(__file__).resolve().parents[2]


def cap(velocity, maximum):
    if maximum <= 0:
        return velocity
    speed = math.hypot(*velocity)
    return tuple(x * min(1.0, maximum / speed) for x in velocity) if speed > 0 else velocity


class LinearSpeedContracts(unittest.TestCase):
    def test_wiring_and_settings(self):
        for dim in ("2d", "3d"):
            key = f"physics/{dim}/solver/max_linear_velocity"
            self.assertIn(key, (ROOT / f"servers/physics_{dim}/physics_server_{dim}.cpp").read_text())
            self.assertIn(key, (ROOT / f"modules/godot_physics_{dim}/godot_space_{dim}.cpp").read_text())
            self.assertIn("max_linear_velocity = 0.0", (ROOT / f"modules/godot_physics_{dim}/godot_space_{dim}.h").read_text())
            source = (ROOT / f"modules/godot_physics_{dim}/godot_body_{dim}.cpp").read_text()
            self.assertEqual(source.count("godot_physics_clamp_linear_velocity(linear_velocity, get_space()->get_max_linear_velocity())"), 2)
            self.assertIn("BODY_MODE_KINEMATIC", source)

    def test_2d_3d_limits_and_directions(self):
        for velocity in ((0, 0), (3, 4), (-6, 8), (1, 2, 3), (0, 0, -10)):
            for maximum in (0, 1, 3, 5, 100):
                candidate = cap(velocity, maximum)
                if maximum <= 0:
                    self.assertEqual(candidate, velocity)
                else:
                    self.assertLessEqual(math.hypot(*candidate), maximum + 1e-12)
                    self.assertTrue(all(a * b >= 0 for a, b in zip(velocity, candidate)))

    def test_cpp_coverage(self):
        helper = (ROOT / "servers/physics_linear_velocity_cap.h").read_text()
        tests = (ROOT / "tests/servers/test_godot_physics_linear_velocity_cap.cpp").read_text()
        self.assertIn("p_velocity.length_squared()", helper)
        self.assertIn("TEST_FORCE_LINK(test_godot_physics_linear_velocity_cap)", tests)
        self.assertGreaterEqual(tests.count("SUBCASE("), 5)


if __name__ == "__main__":
    unittest.main()
