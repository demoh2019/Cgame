"""Contracts for conservative nonlinear 2D capsule-versus-segment CCD."""

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "servers" / "physics_ccd_rotating_capsule_segment_toi.h"
SOLVER = ROOT / "modules" / "godot_physics_2d" / "godot_body_pair_2d.cpp"
CPP_TEST = ROOT / "tests" / "servers" / "test_physics_ccd_rotating_capsule_segment_toi.cpp"
SCENARIO = ROOT / "tests" / "stress" / "physics_ccd_rotating_capsule_segment_2d_regression.gd"
WORKFLOW = ROOT / ".github" / "workflows" / "whole-engine-stress.yml"


class RotatingCapsuleSegmentTOIContracts(unittest.TestCase):
    def test_non_linear_conservative_advance_uses_segment_distance(self):
        source = HELPER.read_text(encoding="utf-8")
        self.assertIn('"servers/physics_ccd_capsule_pair_toi.h"', source)
        self.assertIn('"servers/physics_ccd_rotating_capsule_toi.h"', source)
        self.assertIn("const double maximum_travel = angular_speed * double(p_step)", source)
        self.assertIn("for (int i = 0; i < 48; ++i)", source)
        self.assertIn("physics_ccd_rotate_vector(initial_center_offset, p_omega, seconds)", source)
        self.assertIn("physics_ccd_rotate_vector(initial_axis, p_omega, seconds)", source)
        self.assertIn("const Distance nearest = distance_at(", source)
        self.assertIn("const double gap = Math::sqrt(nearest.squared) - p_capsule_radius;", source)
        self.assertIn("gap - epsilon > maximum_travel * remaining", source)
        self.assertIn("const double progress = gap * 0.95 / maximum_travel;", source)
        self.assertIn("return PhysicsCCDRotatingCapsuleTOIResult::FALLBACK;", source)

    def test_native_branch_requires_opt_in_and_one_way_safety(self):
        source = SOLVER.read_text(encoding="utf-8")
        begin = source.index("bool GodotBodyPair2D::_test_ccd(")
        end = source.index("bool GodotBodyPair2D::setup(", begin)
        cast = source[begin:end]
        self.assertIn('#include "servers/physics_ccd_rotating_capsule_segment_toi.h"', source)
        self.assertIn("physics_ccd_rotating_capsule_segment_toi(", cast)
        self.assertIn("space->is_ccd_rotational_bounds_enabled()", cast)
        self.assertIn("p_A->get_shape(p_shape_A)->get_type() == PS2DE::SHAPE_CAPSULE", cast)
        self.assertIn("p_B->get_shape(p_shape_B)->get_type() == PS2DE::SHAPE_SEGMENT", cast)
        self.assertIn("!p_B->is_shape_set_as_one_way_collision(p_shape_B)", cast)
        self.assertIn("p_A->get_transform().get_origin() + p_A->get_center_of_mass()", cast)
        self.assertIn("p_A->set_angular_velocity(p_A->get_angular_velocity() * fraction)", cast)

    def test_cpp_and_engine_tests_cover_rotation_tunneling_and_translated_pivots(self):
        cpp = CPP_TEST.read_text(encoding="utf-8")
        self.assertIn("TEST_FORCE_LINK(test_physics_ccd_rotating_capsule_segment_toi)", cpp)
        self.assertIn("[RotatingCapsuleSegmentTOI]", cpp)
        self.assertIn("Rotation hits a finite segment and exits within a step", cpp)
        self.assertIn("Offset pivot and world translation preserve first contact", cpp)
        self.assertIn("Miss, overlap and degenerate segment", cpp)
        gd = SCENARIO.read_text(encoding="utf-8")
        self.assertIn("Vector2(2048.0, -4096.0)", gd)
        self.assertIn("PhysicsServer2D.BODY_PARAM_CENTER_OF_MASS", gd)
        self.assertIn("physics/2d/solver/ccd_rotational_bounds", gd)
        self.assertIn("2D rotating capsule-segment CCD regression passed.", gd)
        ci = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn('--test-case="*RotatingCapsuleSegmentTOI*"', ci)
        self.assertIn(SCENARIO.name, ci)
        self.assertIn("physics2d-rotating-capsule-segment-toi.log", ci)
        self.assertIn("physics2d-rotating-capsule-segment-ccd.log", ci)


if __name__ == "__main__":
    unittest.main()
