"""Source and integration contracts for analytic circle/sphere time of impact.

The numeric C++ tests live in tests/servers/test_physics_ccd_sphere_toi.cpp.
Native motion tests are the two relative-motion CCD scripts.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "servers" / "physics_ccd_sphere_toi.h"
CCD_2D = ROOT / "modules" / "godot_physics_2d" / "godot_body_pair_2d.cpp"
CCD_3D = ROOT / "modules" / "godot_physics_3d" / "godot_body_pair_3d.cpp"
WORKFLOW = ROOT / ".github" / "workflows" / "whole-engine-stress.yml"


class SphereTimeOfImpactContracts(unittest.TestCase):
    def test_helper_uses_stable_root_and_double_intermediates(self):
        source = HELPER.read_text(encoding="utf-8")
        self.assertIn("const double a =", source)
        self.assertIn("const double b =", source)
        self.assertIn("const double c =", source)
        self.assertIn("const double fraction = c / denominator;", source)
        self.assertIn("const double discriminant = b * b - a * c;", source)
        self.assertIn("fraction >= 0.0 && fraction <= 1.0", source)

    def test_2d_uses_analytic_toi_with_affine_and_rotation_fallback(self):
        source = CCD_2D.read_text(encoding="utf-8")
        self.assertIn('servers/physics_ccd_sphere_toi.h', source)
        self.assertIn("PS2DE::SHAPE_CIRCLE && shape_B_ptr->get_type() == PS2DE::SHAPE_CIRCLE", source)
        self.assertIn("physics_ccd_uniform_sphere_scale(p_xform_A)", source)
        self.assertIn("physics_ccd_uniform_sphere_scale(p_xform_B)", source)
        self.assertIn("physics_ccd_sphere_toi(center_delta, relative_motion, radius_A + radius_B", source)
        self.assertIn("p_A->get_angular_velocity() == 0.0", source)
        self.assertIn("p_B->get_angular_velocity() == 0.0", source)
        self.assertIn("const Vector2 inv_B", source.replace("const Transform2D inv_B", "const Vector2 inv_B"))

    def test_3d_uses_analytic_toi_with_affine_and_rotation_fallback(self):
        source = CCD_3D.read_text(encoding="utf-8")
        self.assertIn('servers/physics_ccd_sphere_toi.h', source)
        self.assertIn("PS3DE::SHAPE_SPHERE && shape_B_ptr->get_type() == PS3DE::SHAPE_SPHERE", source)
        self.assertIn("physics_ccd_uniform_sphere_scale(p_xform_A)", source)
        self.assertIn("physics_ccd_uniform_sphere_scale(p_xform_B)", source)
        self.assertIn("physics_ccd_sphere_toi(center_delta, relative_motion, radius_A + radius_B", source)
        self.assertIn("p_A->get_angular_velocity() == Vector3()", source)
        self.assertIn("p_B->get_angular_velocity() == Vector3()", source)
        self.assertIn("const Transform3D inverse_B", source)

    def test_cpp_and_native_regressions_are_discoverable(self):
        unit = ROOT / "tests" / "servers" / "test_physics_ccd_sphere_toi.cpp"
        self.assertIn("TEST_FORCE_LINK(test_physics_ccd_sphere_toi)", unit.read_text(encoding="utf-8"))
        workflow = WORKFLOW.read_text(encoding="utf-8")
        for dimension in ("2d", "3d"):
            script_name = f"physics_ccd_relative_motion_{dimension}_regression.gd"
            source = (ROOT / "tests" / "stress" / script_name).read_text(encoding="utf-8")
            self.assertIn("glancing sphere CCD", source)
            self.assertIn(script_name, workflow)


if __name__ == "__main__":
    unittest.main()
