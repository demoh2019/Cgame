"""Source and numerical regression contracts for PhysX-style static friction."""

from pathlib import Path
import math
import unittest

ROOT = Path(__file__).resolve().parents[2]


def static_friction(candidate, dynamic_limit, multiplier):
    static_limit = max(dynamic_limit, 0) * max(multiplier, 1)
    if abs(candidate) <= static_limit:
        return candidate
    return max(-dynamic_limit, min(candidate, dynamic_limit))


class StaticFrictionContracts(unittest.TestCase):
    def test_per_space_setting(self):
        for dim in ("2d", "3d"):
            key = f"physics/{dim}/solver/static_friction_multiplier"
            server = (ROOT / f"servers/physics_{dim}/physics_server_{dim}.cpp").read_text()
            space_cpp = (ROOT / f"modules/godot_physics_{dim}/godot_space_{dim}.cpp").read_text()
            space_h = (ROOT / f"modules/godot_physics_{dim}/godot_space_{dim}.h").read_text()
            self.assertIn(key, server)
            self.assertIn(key, space_cpp)
            self.assertIn("static_friction_multiplier = 1.0", space_h)
            self.assertIn("get_static_friction_multiplier()", space_h)

    def test_all_three_contact_types(self):
        sources = [(ROOT / f"modules/godot_physics_{dim}/godot_body_pair_{dim}.cpp").read_text()
                   for dim in ("2d", "3d")]
        self.assertIn("godot_physics_clamp_static_friction_2d(", sources[0])
        self.assertEqual(sources[1].count("godot_physics_clamp_static_friction_3d("), 2)
        self.assertIn("const real_t static_friction_multiplier = space->get_static_friction_multiplier();", sources[0])
        self.assertEqual(sources[1].count("const real_t static_friction_multiplier = space->get_static_friction_multiplier();"), 2)
        self.assertIn("cached_tangent_limit = mixed_friction * space->get_static_friction_multiplier()", sources[0])
        self.assertIn("cached_tangent_limit = mixed_friction * space->get_static_friction_multiplier()", sources[1])
        self.assertIn("tangent_limit = friction * space->get_static_friction_multiplier()", sources[1])

    def test_default_keeps_single_coefficient(self):
        for c in (-5, -1, -0.4, 0, 0.4, 1, 5):
            for friction in (0, 0.1, 0.5, 2):
                self.assertAlmostEqual(static_friction(c, friction, 1), max(-friction, min(c, friction)))

    def test_stick_and_slide(self):
        self.assertAlmostEqual(static_friction(0.9, 0.5, 2), 0.9)
        self.assertAlmostEqual(static_friction(-0.9, 0.5, 2), -0.9)
        self.assertAlmostEqual(static_friction(1.2, 0.5, 2), 0.5)
        self.assertAlmostEqual(static_friction(-1.2, 0.5, 2), -0.5)

    def test_native_coverage(self):
        tests = (ROOT / "tests/servers/test_godot_physics_contact_static_friction.cpp").read_text()
        self.assertIn("TEST_FORCE_LINK(test_godot_physics_contact_static_friction)", tests)
        self.assertGreaterEqual(tests.count('SUBCASE('), 6)


if __name__ == "__main__":
    unittest.main()
