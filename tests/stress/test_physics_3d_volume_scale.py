"""Guard GodotPhysics3D volume cache against costly scale decomposition."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]


class Physics3DVolumeScaleContracts(unittest.TestCase):
    def test_shape_volume_uses_determinant_not_scale_decomposition(self):
        source = (ROOT / "modules/godot_physics_3d/godot_collision_object_3d.cpp").read_text(encoding="utf-8")
        self.assertIn("godot_physics_3d_volume_scale(xform.basis)", source)
        self.assertNotIn("xform.get_basis().get_scale()", source)

    def test_volume_helper_uses_positive_determinant(self):
        helper = (ROOT / "modules/godot_physics_3d/godot_shape_volume_3d.h").read_text(encoding="utf-8")
        self.assertIn("Math::abs(p_basis.determinant())", helper)

    def test_native_math_cases_are_linked(self):
        tests = (ROOT / "tests/servers/test_godot_physics_3d_volume_scale.cpp").read_text(encoding="utf-8")
        self.assertIn("TEST_FORCE_LINK(test_godot_physics_3d_volume_scale)", tests)
        self.assertGreaterEqual(tests.count("SUBCASE("), 6)


if __name__ == "__main__":
    unittest.main()
