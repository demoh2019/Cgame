"""Source contracts for allocation-free circle/sphere vs capsule linear TOI.

Numerical C++ tests live in tests/servers/test_physics_ccd_capsule_toi.cpp.
The native CCD scenarios run from whole-engine-stress.yml.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "servers" / "physics_ccd_capsule_toi.h"
CPP_TEST = ROOT / "tests" / "servers" / "test_physics_ccd_capsule_toi.cpp"
WORKFLOW = ROOT / ".github" / "workflows" / "whole-engine-stress.yml"


class CapsuleTimeOfImpactContracts(unittest.TestCase):
    def test_helper_uses_closest_approach_and_earliest_entry(self):
        source = HELPER.read_text(encoding="utf-8")
        self.assertIn("const double lateral_squared =", source)
        self.assertIn("const double projection = ", source)
        self.assertIn("const double gap = ", source)
        self.assertIn("Math::sqrt(gap / lateral_squared)", source)
        self.assertIn("Math::sqrt(gap / a)", source)
        self.assertIn("t >= 0.0 && t <= 1.0", source)
        self.assertIn("t < 0.0 || t > 1.0 || t >= best", source)
        self.assertIn("best >= 0.0 && best <= 1.0", source)

    def test_native_2d_circle_capsule_cast_has_affine_fallback(self):
        source = (ROOT / "modules" / "godot_physics_2d" / "godot_body_pair_2d.cpp").read_text(encoding="utf-8")
        self.assertIn('"servers/physics_ccd_capsule_toi.h"', source)
        self.assertIn("PS2DE::SHAPE_CIRCLE && shape_B_ptr->get_type() == PS2DE::SHAPE_CAPSULE", source)
        self.assertIn("const Transform2D inverse_B = p_xform_B.affine_inverse()", source)
        self.assertIn("physics_ccd_uniform_sphere_scale(p_xform_B)", source)
        self.assertIn("physics_ccd_capsule_toi(local_start, local_motion", source)
        self.assertIn("p_A->set_linear_velocity(travel_direction * clipped_speed)", source)
        self.assertIn("Vector2 supports_A[2]", source)
        self.assertIn("PS2DE::SHAPE_CAPSULE && shape_B_ptr->get_type() == PS2DE::SHAPE_CIRCLE", source)
        self.assertIn("const Vector2 local_motion = -inverse_A.basis_xform(relative_motion)", source)

    def test_native_3d_sphere_capsule_cast_has_affine_fallback(self):
        source = (ROOT / "modules" / "godot_physics_3d" / "godot_body_pair_3d.cpp").read_text(encoding="utf-8")
        self.assertIn('"servers/physics_ccd_capsule_toi.h"', source)
        self.assertIn("PS3DE::SHAPE_SPHERE && shape_B_ptr->get_type() == PS3DE::SHAPE_CAPSULE", source)
        self.assertIn("const Transform3D inverse_B = p_xform_B.affine_inverse()", source)
        self.assertIn("physics_ccd_uniform_sphere_scale(p_xform_B)", source)
        self.assertIn("physics_ccd_capsule_toi(local_start, local_motion", source)
        self.assertIn("p_A->set_linear_velocity(travel_direction * clipped_speed)", source)
        self.assertIn("Vector3 supports[MAX_CCD_SUPPORTS]", source)
        self.assertIn("PS3DE::SHAPE_CAPSULE && shape_B_ptr->get_type() == PS3DE::SHAPE_SPHERE", source)
        self.assertIn("const Vector3 local_motion = -inverse_A.basis.xform(relative_motion)", source)

    def test_parallel_2d_capsules_use_axial_minkowski_sum(self):
        source = (ROOT / "modules" / "godot_physics_2d" / "godot_body_pair_2d.cpp").read_text(encoding="utf-8")
        self.assertIn("PS2DE::SHAPE_CAPSULE && shape_B_ptr->get_type() == PS2DE::SHAPE_CAPSULE", source)
        self.assertIn("p_A->get_angular_velocity() == 0.0 && p_B->get_angular_velocity() == 0.0", source)
        self.assertIn("Math::abs(double(axis_A.cross(axis_B)))", source)
        self.assertIn("const double ratio = scale_A / scale_B;", source)
        self.assertIn("radius_B + radius_A * ratio, half_B + half_A * ratio", source)
        self.assertIn("const Vector2 local_motion = inverse_B.basis_xform(relative_motion)", source)
        self.assertIn("Vector2 supports_A[2]", source)

    def test_parallel_3d_capsules_use_axial_minkowski_sum(self):
        source = (ROOT / "modules" / "godot_physics_3d" / "godot_body_pair_3d.cpp").read_text(encoding="utf-8")
        self.assertIn("PS3DE::SHAPE_CAPSULE && shape_B_ptr->get_type() == PS3DE::SHAPE_CAPSULE", source)
        self.assertIn("p_A->get_angular_velocity() == Vector3() && p_B->get_angular_velocity() == Vector3()", source)
        self.assertIn("axis_A.cross(axis_B).length()", source)
        self.assertIn("const double ratio = scale_A / scale_B;", source)
        self.assertIn("radius_B + radius_A * ratio, half_B + half_A * ratio", source)
        self.assertIn("const Vector3 local_motion = inverse_B.basis.xform(relative_motion)", source)
        self.assertIn("Vector3 supports[MAX_CCD_SUPPORTS]", source)

    def test_cpp_and_native_coverage_reachable_from_ci(self):
        cpp = CPP_TEST.read_text(encoding="utf-8")
        self.assertIn("TEST_FORCE_LINK(test_physics_ccd_capsule_toi)", cpp)
        self.assertIn("[CapsuleTOI]", cpp)
        self.assertIn('test-case="*CapsuleTOI*"', WORKFLOW.read_text(encoding="utf-8"))
        self.assertIn("glancing end-cap impact", cpp)
        workflow = WORKFLOW.read_text(encoding="utf-8")
        for dim in ("2d", "3d"):
            script_name = f"physics_ccd_relative_motion_{dim}_regression.gd"
            script = (ROOT / "tests" / "stress" / script_name).read_text(encoding="utf-8")
            self.assertIn("glancing capsule CCD", script)
            self.assertIn("moving capsule CCD", script)
            self.assertIn("parallel capsules CCD", script)
            self.assertIn("antiparallel capsules CCD", script)
            self.assertIn(script_name, workflow)


if __name__ == "__main__":
    unittest.main()
