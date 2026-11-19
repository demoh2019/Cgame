"""Source and CI contracts for skew (nonparallel) 2D/3D capsule CCD."""

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "servers" / "physics_ccd_capsule_pair_toi.h"
CPP_TEST = ROOT / "tests" / "servers" / "test_physics_ccd_capsule_pair_toi.cpp"
WORKFLOW = ROOT / ".github" / "workflows" / "whole-engine-stress.yml"


class SkewCapsuleTOIContracts(unittest.TestCase):
    def test_minimum_separation_uses_double_and_bounded_search(self):
        source = HELPER.read_text(encoding="utf-8")
        self.assertIn("struct Vec3", source)
        self.assertIn("double derivative_half;", source)
        self.assertIn("const double segment_a_squared = dot(segment_a, segment_a);", source)
        self.assertIn("const double segment_b_squared = dot(segment_b, segment_b);", source)
        self.assertIn("const double segment_dot = dot(segment_a, segment_b);", source)
        self.assertIn("const Vec3 normal = cross(axis_a, axis_b);", source)
        self.assertIn("const double separation_begin = dot(normal, center);", source)
        self.assertIn("const double separation_end = separation_begin + dot(normal, motion);", source)
        self.assertIn("dot(nearest, nearest), dot(nearest, p_motion)", source)
        self.assertIn("const int search_iterations = sizeof(real_t) == sizeof(float) ? 32 : 48;", source)
        self.assertEqual(source.count("for (int i = 0; i < search_iterations; ++i)"), 2)
        self.assertIn("minimum.squared <= radius_sq", source)
        self.assertIn("r_fraction = high;", source)

    def test_initial_overlap_and_degenerate_inputs_preserve_fallback(self):
        source = HELPER.read_text(encoding="utf-8")
        self.assertIn("enum class PhysicsCCDCapsulePairTOIResult", source)
        self.assertIn("PhysicsCCDCapsulePairTOIResult::FALLBACK", source)
        self.assertIn("PhysicsCCDCapsulePairTOIResult::MISS", source)
        self.assertIn("PhysicsCCDCapsulePairTOIResult::HIT", source)
        self.assertIn("if (!(start.squared > radius_sq))", source)

    def test_skew_capsule_pair_integrates_in_both_backends(self):
        for dim, pair, vector, origin in (
            ("2d", "PS2DE::SHAPE_CAPSULE", "Vector2", "p_xform_A.get_origin()"),
            ("3d", "PS3DE::SHAPE_CAPSULE", "Vector3", "p_xform_A.origin"),
        ):
            code = (ROOT / "modules" / f"godot_physics_{dim}" / f"godot_body_pair_{dim}.cpp").read_text(encoding="utf-8")
            self.assertIn('#include "servers/physics_ccd_capsule_pair_toi.h"', code)
            self.assertIn(f"shape_A_ptr->get_type() == {pair} && shape_B_ptr->get_type() == {pair}", code)
            self.assertIn("physics_ccd_uniform_sphere_scale(p_xform_A)", code)
            self.assertIn("physics_ccd_uniform_sphere_scale(p_xform_B)", code)
            self.assertIn(origin, code)
            self.assertIn("const PhysicsCCDCapsulePairTOIResult result = physics_ccd_capsule_pair_toi(", code)
            self.assertIn("result == PhysicsCCDCapsulePairTOIResult::MISS", code)
            self.assertIn("result == PhysicsCCDCapsulePairTOIResult::HIT", code)
            self.assertIn(f"const {vector} travel_direction = velocity_A / initial_speed;", code)

    def test_targeted_cpp_and_runtime_tests_execute_in_native_ci(self):
        cpp = CPP_TEST.read_text(encoding="utf-8")
        self.assertIn("TEST_FORCE_LINK(test_physics_ccd_capsule_pair_toi)", cpp)
        self.assertIn("[CapsulePairTOI]", cpp)
        self.assertIn("Perpendicular 2D capsules", cpp)
        self.assertIn("Skew 3D capsule", cpp)
        self.assertIn("Swept cross-axis separation", cpp)
        workflow = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn('test-case="*CapsulePairTOI*"', workflow)
        self.assertIn("physics-capsule-pair-toi.log", workflow)
        for dim in ("2d", "3d"):
            filename = f"physics_ccd_relative_motion_{dim}_regression.gd"
            script = (ROOT / "tests" / "stress" / filename).read_text(encoding="utf-8")
            self.assertIn('"skew capsules CCD"', script)
            self.assertIn("skew_source_axis: bool = false", script)
            self.assertIn(filename, workflow)


if __name__ == "__main__":
    unittest.main()
