"""Source and numerical contracts for Jolt-style GodotPhysics angular speed limits."""

from pathlib import Path
import math
import unittest

ROOT = Path(__file__).resolve().parents[2]


def cap_scalar(angular_velocity, maximum):
    if maximum <= 0:
        return angular_velocity
    return max(-maximum, min(maximum, angular_velocity))


def cap_vector(angular_velocity, maximum):
    if maximum <= 0:
        return angular_velocity
    length = math.hypot(*angular_velocity)
    scale = min(1.0, maximum / length) if length else 1.0
    return tuple(x * scale for x in angular_velocity)


class AngularVelocityCapContracts(unittest.TestCase):
    def test_registered_and_cached_for_both_dimensions(self):
        for dim in ("2d", "3d"):
            with self.subTest(dim=dim):
                path = f"physics/{dim}/solver/max_angular_velocity"
                server = (ROOT / f"servers/physics_{dim}/physics_server_{dim}.cpp").read_text()
                space_cpp = (ROOT / f"modules/godot_physics_{dim}/godot_space_{dim}.cpp").read_text()
                space_h = (ROOT / f"modules/godot_physics_{dim}/godot_space_{dim}.h").read_text()
                self.assertIn(path, server)
                self.assertIn(path, space_cpp)
                self.assertIn("real_t max_angular_velocity = 0.0", space_h)
                self.assertIn("get_max_angular_velocity()", space_h)

    def test_both_phases_and_kinematic_exemption(self):
        for dim in ("2d", "3d"):
            source = (ROOT / f"modules/godot_physics_{dim}/godot_body_{dim}.cpp").read_text()
            marker = "godot_physics_clamp_angular_velocity(angular_velocity, get_space()->get_max_angular_velocity())"
            with self.subTest(dim=dim):
                self.assertEqual(source.count(marker), 2)
                first = source.index("void GodotBody" + ("2D" if dim == "2d" else "3D") + "::integrate_velocities(")
                kinematic = source.index("BODY_MODE_KINEMATIC", first)
                self.assertLess(kinematic, source.rindex(marker))
                self.assertIn("angular_velocity + biased_angular_velocity", source)

    def test_numerical_bounds_and_direction(self):
        for maximum in (0, 1, 5, 10):
            for angular_velocity in (-50, -2, 0, 3, 50):
                next_value = cap_scalar(angular_velocity, maximum)
                with self.subTest(value=angular_velocity, max_speed=maximum):
                    if maximum > 0:
                        self.assertLessEqual(abs(next_value), maximum)
                    else:
                        self.assertEqual(next_value, angular_velocity)
            for vector in ((0, 0, 0), (30, 40, 0), (-1e20, 1e20, 0)):
                candidate = cap_vector(vector, maximum)
                with self.subTest(vector=vector, max_speed=maximum):
                    if maximum > 0:
                        self.assertLessEqual(math.hypot(*candidate), maximum + 1e-8)
                        self.assertTrue(all(a * b >= 0 for a, b in zip(vector, candidate)))
                    else:
                        self.assertEqual(candidate, vector)

    def test_native_tests_and_overflow_safe_3d(self):
        helper = (ROOT / "servers/physics_angular_velocity_cap.h").read_text()
        tests = (ROOT / "tests/servers/test_godot_physics_angular_velocity_cap.cpp").read_text()
        self.assertIn("godot_physics_clamp_linear_velocity(p_angular_velocity, p_max_speed)", helper)
        self.assertIn("TEST_FORCE_LINK(test_godot_physics_angular_velocity_cap)", tests)
        self.assertGreaterEqual(tests.count("SUBCASE("), 5)


if __name__ == "__main__":
    unittest.main()
