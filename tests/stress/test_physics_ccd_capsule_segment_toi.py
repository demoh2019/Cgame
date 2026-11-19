"""Contracts for native 2D capsule/segment swept-volume CCD.

The pair uses finite-segment distance TOI rather than endpoint support rays.
The native CI runs C++ geometry tests and moving-body GDScript regressions.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "servers" / "physics_ccd_capsule_segment_toi.h"
SOLVER = ROOT / "modules" / "godot_physics_2d" / "godot_body_pair_2d.cpp"
CPP_TEST = ROOT / "tests" / "servers" / "test_physics_ccd_capsule_segment_toi.cpp"
SCENARIO = ROOT / "tests" / "stress" / "physics_ccd_capsule_segment_2d_regression.gd"
WORKFLOW = ROOT / ".github" / "workflows" / "whole-engine-stress.yml"


class CapsuleSegmentTOIContracts(unittest.TestCase):
    def test_capsule_segment_reuses_volume_toi_and_handles_zero_length(self):
        code = HELPER.read_text(encoding="utf-8")
        self.assertIn('"servers/physics_ccd_capsule_pair_toi.h"', code)
        self.assertIn("const double sx = bx - ax;", code)
        self.assertIn("const double length_squared = sx * sx + sy * sy;", code)
        self.assertIn("const double half_segment = Math::sqrt(length_squared) * 0.5;", code)
        self.assertIn("half_segment > 0.0 ?", code)
        self.assertIn("p_capsule_center - segment_center, p_relative_motion,", code)
        self.assertIn("p_capsule_half_segment, half_segment, p_capsule_radius, r_fraction", code)

    def test_solver_is_symmetric_and_rejects_rotation_or_nonuniform_capsules(self):
        code = SOLVER.read_text(encoding="utf-8")
        self.assertIn('"servers/physics_ccd_capsule_segment_toi.h"', code)
        self.assertIn("PS2DE::SHAPE_CAPSULE && shape_B_ptr->get_type() == PS2DE::SHAPE_SEGMENT", code)
        self.assertIn("PS2DE::SHAPE_SEGMENT && shape_B_ptr->get_type() == PS2DE::SHAPE_CAPSULE", code)
        self.assertIn("capsule_is_A ? relative_motion : -relative_motion", code)
        self.assertIn("physics_ccd_uniform_sphere_scale(capsule_transform)", code)
        self.assertIn("capsule_transform.columns[1]", code)
        self.assertIn("segment_transform.xform(segment->get_a())", code)
        self.assertIn("segment_transform.xform(segment->get_b())", code)
        self.assertIn("p_A->get_angular_velocity() == 0.0 && p_B->get_angular_velocity() == 0.0", code)
        self.assertIn("result == PhysicsCCDCapsulePairTOIResult::HIT", code)

    def test_both_volume_segment_paths_preserve_one_way_platforms(self):
        source = SOLVER.read_text(encoding="utf-8")
        start = source.index("bool GodotBodyPair2D::_test_ccd(")
        end = source.index("bool GodotBodyPair2D::setup(", start)
        cast = source[start:end]
        for result in ("PhysicsCCDCircleSegmentTOIResult", "PhysicsCCDCapsulePairTOIResult"):
            start = cast.index(f"if (result == {result}::HIT)")
            guard = cast[start: start + 1100]
            self.assertIn("p_B->is_shape_set_as_one_way_collision(p_shape_B)", guard)
            self.assertIn("one_way_direction.dot(mnormal) < CMP_EPSILON", guard)
            self.assertIn("oneway_disabled = true;", guard)

    def test_cpp_and_engine_regressions_are_in_native_ci(self):
        cpp = CPP_TEST.read_text(encoding="utf-8")
        self.assertIn("TEST_FORCE_LINK(test_physics_ccd_capsule_segment_toi)", cpp)
        self.assertIn("[CapsuleSegmentTOI]", cpp)
        self.assertIn("Vertical capsule sweeps glancing horizontal segment endpoint", cpp)
        self.assertIn("Horizontal capsule contacts vertical segment", cpp)
        script = SCENARIO.read_text(encoding="utf-8")
        for case in (
            "moving capsule grazes segment endpoint",
            "moving segment grazes static capsule",
            "capsule segment separated",
            "one-way capsule segment backface",
        ):
            self.assertIn(case, script)
        self.assertIn("body_set_shape_as_one_way_collision", script)
        workflow = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn('--test-case="*CapsuleSegmentTOI*"', workflow)
        self.assertIn(SCENARIO.name, workflow)
        self.assertIn("physics2d-capsule-segment-toi.log", workflow)
        self.assertIn("physics2d-capsule-segment-ccd.log", workflow)


if __name__ == "__main__":
    unittest.main()
