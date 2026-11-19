"""Source wiring and numerical contracts for Box2D-style penetration recovery cap."""

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def limit_bias(bias: float, maximum: float) -> float:
    return min(bias, maximum) if maximum > 0 else bias


class ContactPushSpeedContracts(unittest.TestCase):
    def test_setting_and_space_caching(self):
        for dim in ("2d", "3d"):
            with self.subTest(dim=dim):
                key = f"physics/{dim}/solver/max_contact_push_speed"
                server = (ROOT / f"servers/physics_{dim}/physics_server_{dim}.cpp").read_text()
                source = (ROOT / f"modules/godot_physics_{dim}/godot_space_{dim}.cpp").read_text()
                header = (ROOT / f"modules/godot_physics_{dim}/godot_space_{dim}.h").read_text()
                self.assertIn(key, server)
                self.assertIn(key, source)
                self.assertIn("godot_physics_limit_contact_bias(p_bias, max_contact_push_speed)", header)

    def test_all_contact_solver_paths(self):
        source_2d = (ROOT / "modules/godot_physics_2d/godot_body_pair_2d.cpp").read_text()
        source_3d = (ROOT / "modules/godot_physics_3d/godot_body_pair_3d.cpp").read_text()
        marker = "c.bias = space->limit_contact_bias(-bias * inv_dt * MIN(0.0f, -depth + max_penetration));"
        self.assertEqual(source_2d.count(marker), 1, "2D rigid contacts")
        self.assertEqual(source_3d.count(marker), 2, "3D rigid and rigid-soft contacts")

    def test_default_disabled_and_cap(self):
        for bias in (0, 1, 1e3, 1e9):
            for speed in (0, -1, 1, 10, 100):
                result = limit_bias(bias, speed)
                self.assertEqual(result, bias if speed <= 0 else min(bias, speed))
                self.assertLessEqual(result, bias)

    def test_native_registration(self):
        helper = (ROOT / "servers/physics_contact_push_speed.h").read_text()
        tests = (ROOT / "tests/servers/test_godot_physics_contact_push_speed.cpp").read_text()
        self.assertIn("p_max_push_speed > real_t(0.0)", helper)
        self.assertIn("TEST_FORCE_LINK(test_godot_physics_contact_push_speed)", tests)


if __name__ == "__main__":
    unittest.main()
