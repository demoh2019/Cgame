"""Guard native 3D cast-ray CCD relative sweeps, transform caching, and safe velocity clipping.

The engine-level regression lives in physics_ccd_relative_motion_3d_regression.gd.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "modules" / "godot_physics_3d" / "godot_body_pair_3d.cpp"
REGRESSION = ROOT / "tests" / "stress" / "physics_ccd_relative_motion_3d_regression.gd"
WORKFLOW = ROOT / ".github" / "workflows" / "whole-engine-stress.yml"


class CCDTransformCacheContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source = SOURCE.read_text(encoding="utf-8")
        begin = source.index("bool GodotBodyPair3D::_test_ccd(")
        end = source.index("bool GodotBodyPair3D::setup(", begin)
        cls.routine = source[begin:end]

    def test_target_inverse_computed_once_before_support_loop(self):
        routine = self.routine
        loop = routine.index("for (int i = 0; i < support_count; ++i)")
        self.assertEqual(routine.count("p_xform_B.affine_inverse()"), 1)
        self.assertLess(routine.index("const Transform3D inverse_B"), loop)
        self.assertNotIn("affine_inverse()", routine[loop:])

    def test_target_shape_lookup_is_outside_support_loop(self):
        routine = self.routine
        loop = routine.index("for (int i = 0; i < support_count; ++i)")
        self.assertLess(routine.index("GodotShape3D *shape_B_ptr"), loop)
        self.assertNotIn("p_B->get_shape(p_shape_B)", routine[loop:])
        self.assertIn("shape_B_ptr->intersect_segment", routine[loop:])

    def test_relative_sweep_in_current_target_frame(self):
        routine = self.routine
        self.assertIn("relative_motion = motion_A - velocity_B * p_step", routine)
        self.assertIn("inverse_B.xform(from - relative_motion * real_t(0.1))", routine)
        self.assertIn("inverse_B.xform(from + relative_motion)", routine)
        self.assertNotIn("predicted_xform_B", routine)

    def test_hit_order_is_world_space_and_velocity_is_bounded(self):
        routine = self.routine
        self.assertIn("direction.dot(p_xform_B.xform(hit_point) - from)", routine)
        self.assertIn("hit_distance < best_hit_distance", routine)
        self.assertIn("motion_A.dot(relative_motion) <= 0.0", routine)
        self.assertIn("const real_t clipped_speed = CLAMP(", routine)
        self.assertIn("travel_direction * clipped_speed", routine)

    def test_static_surface_velocity_does_not_move_geometry(self):
        self.assertIn("p_B->get_mode() == PS3DE::BODY_MODE_STATIC", self.routine)

    def test_native_regression_in_ci(self):
        script = REGRESSION.read_text(encoding="utf-8")
        for name in ("co-moving bodies", "slower trailing body", "slower body ahead",
                     "static conveyor surface"):
            self.assertIn(name, script)
        self.assertIn("body_set_enable_continuous_collision_detection", script)
        self.assertIn(REGRESSION.name, WORKFLOW.read_text(encoding="utf-8"))

    def test_ccd_stress_workload_is_registered(self):
        import run
        script = (ROOT / "tests" / "stress" / "stress.gd").read_text(encoding="utf-8")
        self.assertIn("physics_ccd_3d", run.CASES)
        self.assertIn('"physics_ccd_3d":', script)
        self.assertIn("func _physics_ccd_3d(", script)
        self.assertIn("body.continuous_cd = true", script)
        self.assertIn("await physics_frame", script)


if __name__ == "__main__":
    unittest.main()
