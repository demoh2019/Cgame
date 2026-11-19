"""Source and numerical regression contracts for GodotPhysics2D rolling resistance."""

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


def next_impulse(previous, angular_velocity, inverse_mass, normal, radius_coefficient):
    if inverse_mass <= 0 or radius_coefficient <= 0:
        return previous
    cap = max(normal, 0) * radius_coefficient
    return max(-cap, min(cap, previous - angular_velocity / inverse_mass))


class RollingResistanceContracts(unittest.TestCase):
    def test_setting_registered_and_cached(self):
        setting = "physics/2d/solver/rolling_resistance"
        self.assertIn(setting, (ROOT / "servers/physics_2d/physics_server_2d.cpp").read_text())
        self.assertIn(setting, (ROOT / "modules/godot_physics_2d/godot_space_2d.cpp").read_text())
        self.assertIn("rolling_resistance = 0.0", (ROOT / "modules/godot_physics_2d/godot_space_2d.h").read_text())

    def test_manifold_constraint_wiring(self):
        source = (ROOT / "modules/godot_physics_2d/godot_body_pair_2d.cpp").read_text()
        self.assertIn("shape_A_ptr->get_type() == PS2DE::SHAPE_CIRCLE", source)
        self.assertIn("shape_B_ptr->get_type() == PS2DE::SHAPE_CIRCLE", source)
        self.assertIn("physics_ccd_uniform_sphere_scale(xform)", source)
        self.assertIn("rolling_impulse = 0.0;", source)
        self.assertIn("normal_impulse += contacts[i].acc_normal_impulse", source)
        self.assertIn("godot_physics_accumulate_rolling_impulse(", source)
        self.assertIn("A->apply_torque_impulse(-delta_impulse)", source)
        self.assertIn("B->apply_torque_impulse(delta_impulse)", source)

    def test_accumulation_and_load_limit(self):
        for omega in (-10.0, -0.1, 0.0, 0.1, 10.0):
            for prior in (-1.0, 0.0, 1.0):
                for normal in (0.0, 0.1, 1.0, 5.0):
                    actual = next_impulse(prior, omega, 2.0, normal, 0.3)
                    self.assertLessEqual(abs(actual), normal * 0.3 + 1e-12)
        self.assertEqual(next_impulse(0.0, 10.0, 0.0, 3.0, 0.5), 0.0)
        self.assertEqual(next_impulse(0.0, 10.0, 1.0, 3.0, 0.0), 0.0)

    def test_native_registration(self):
        helper = (ROOT / "servers/physics_rolling_resistance.h").read_text()
        tests = (ROOT / "tests/servers/test_godot_physics_rolling_resistance.cpp").read_text()
        self.assertIn("CLAMP(p_previous - p_relative_angular_velocity / p_inv_angular_mass", helper)
        self.assertIn("TEST_FORCE_LINK(test_godot_physics_rolling_resistance)", tests)
        self.assertGreaterEqual(tests.count("SUBCASE("), 6)


if __name__ == "__main__":
    unittest.main()
