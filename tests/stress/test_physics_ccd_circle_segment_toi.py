"""Contracts for exact circle versus finite segment CCD in GodotPhysics2D."""

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "servers" / "physics_ccd_circle_segment_toi.h"
SOLVER = ROOT / "modules" / "godot_physics_2d" / "godot_body_pair_2d.cpp"
CPP_TEST = ROOT / "tests" / "servers" / "test_physics_ccd_circle_segment_toi.cpp"
SCENARIO = ROOT / "tests" / "stress" / "physics_ccd_circle_segment_2d_regression.gd"
WORKFLOW = ROOT / ".github" / "workflows" / "whole-engine-stress.yml"


class CircleSegmentTOIContracts(unittest.TestCase):
    def test_swept_volume_uses_capsule_and_double_precision(self):
        code = HELPER.read_text(encoding="utf-8")
        self.assertIn('"servers/physics_ccd_capsule_toi.h"', code)
        self.assertIn("PhysicsCCDCircleSegmentTOIResult::HIT", code)
        self.assertIn("PhysicsCCDCircleSegmentTOIResult::MISS", code)
        self.assertIn("PhysicsCCDCircleSegmentTOIResult::FALLBACK", code)
        self.assertIn("const double sx = bx - ax;", code)
        self.assertIn("const double length_squared = sx * sx + sy * sy;", code)
        self.assertIn("const double center_x = 0.5 * (ax + bx);", code)
        self.assertIn("const double center_y = 0.5 * (ay + by);", code)
        self.assertIn("physics_ccd_capsule_toi(local_x, local_y, 0.0,", code)

    def test_initial_overlap_is_not_a_false_miss(self):
        code = HELPER.read_text(encoding="utf-8")
        self.assertIn("nearest_x * nearest_x + nearest_y * nearest_y <= radius_squared", code)
        self.assertIn("!Math::is_finite(p_circle_radius)", code)
        self.assertIn("!Math::is_finite(length_squared)", code)
        self.assertIn("!Math::is_finite(local_x)", code)

    def test_native_solver_handles_both_shape_orders(self):
        code = SOLVER.read_text(encoding="utf-8")
        self.assertIn('"servers/physics_ccd_circle_segment_toi.h"', code)
        self.assertIn("PS2DE::SHAPE_CIRCLE && shape_B_ptr->get_type() == PS2DE::SHAPE_SEGMENT", code)
        self.assertIn("PS2DE::SHAPE_SEGMENT && shape_B_ptr->get_type() == PS2DE::SHAPE_CIRCLE", code)
        self.assertIn("circle_is_A ? relative_motion : -relative_motion", code)
        self.assertIn("segment_transform.xform(segment->get_a())", code)
        self.assertIn("segment_transform.xform(segment->get_b())", code)
        self.assertIn("physics_ccd_uniform_sphere_scale(circle_transform)", code)
        self.assertIn("const real_t clipped_speed = CLAMP(", code)

    def test_numerical_cpp_and_moving_body_smoke_in_ci(self):
        cpp = CPP_TEST.read_text(encoding="utf-8")
        self.assertIn("TEST_FORCE_LINK(test_physics_ccd_circle_segment_toi)", cpp)
        self.assertIn("[CircleSegmentTOI]", cpp)
        self.assertIn("Glancing entry against a segment endpoint", cpp)
        script = SCENARIO.read_text(encoding="utf-8")
        for name in (
            "glancing circle against segment",
            "moving segment against circle",
            "segment endpoint beyond circle reach",
        ):
            self.assertIn(name, script)
        workflow = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn('--test-case="*CircleSegmentTOI*"', workflow)
        self.assertIn(SCENARIO.name, workflow)
        self.assertIn("physics2d-circle-segment-toi.log", workflow)
        self.assertIn("physics2d-circle-segment-ccd.log", workflow)


if __name__ == "__main__":
    unittest.main()
