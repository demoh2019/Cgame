"""Source contracts for 2D multi-support cast-ray CCD.

The engine-level regression lives in physics_ccd_edge_2d_regression.gd.
These checks guard against silently restoring the single-support shortcut.
"""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "modules/godot_physics_2d" / "godot_body_pair_2d.cpp"
REGRESSION = ROOT / "tests" / "stress" / "physics_ccd_edge_2d_regression.gd"


class CCD2DMultipleSupportsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source = SOURCE.read_text(encoding="utf-8")
        start = source.index("bool GodotBodyPair2D::_test_ccd(")
        end = source.index("real_t combine_bounce(", start)
        cls.cast = source[start:end]

    def test_casts_all_leading_supports(self):
        cast = self.cast
        self.assertIn("Vector2 supports_A[2];", cast)
        self.assertIn("if (support_count_A == 0)", cast)
        self.assertIn(
            "for (int support_idx = 0; support_idx < support_count_A; ++support_idx)",
            cast,
        )
        self.assertIn("supports_A[support_idx]", cast)

    def test_picks_nearest_hit_and_reuses_transform_inverse(self):
        cast = self.cast
        self.assertEqual(cast.count("predicted_xform_B.affine_inverse()"), 1)
        self.assertIn("local_from.distance_squared_to(rpos)", cast)
        self.assertIn("candidate_distance_squared < hit_distance_squared", cast)
        self.assertIn("hit_support_from = from", cast)
        self.assertIn("hitpos.distance_to(hit_support_from)", cast)

    def test_one_way_filter_runs_after_support_casts(self):
        cast = self.cast
        self.assertLess(cast.index("if (!found_hit)"), cast.index("// Check one-way collision"))
        self.assertIn("is_shape_set_as_one_way_collision", cast)

    def test_runtime_regression_exercises_second_support(self):
        script = REGRESSION.read_text(encoding="utf-8")
        self.assertIn("Vector2(0.0, -1.5)", script)
        self.assertIn("CCD_MODE_CAST_RAY", script)
        self.assertIn("result.origin.x < -0.2", script)

    def test_parallel_stress_workload_is_registered(self):
        runner = (ROOT / "tests" / "stress" / "run.py").read_text(encoding="utf-8")
        script = (ROOT / "tests" / "stress" / "stress.gd").read_text(encoding="utf-8")
        self.assertIn('"physics_ccd_2d"', runner)
        self.assertIn('func _physics_ccd_2d(scale: int, frames: int)', script)
        self.assertIn('body.continuous_cd = RigidBody2D.CCD_MODE_CAST_RAY', script)
        self.assertIn('target.position = Vector2(0.0, lane_y - 1.5)', script)
        self.assertIn('return await _physics_ccd_2d(scale, frames)', script)


if __name__ == "__main__":
    unittest.main()
