"""Guard 3D ray-based CCD against per-support transform inversions."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "modules" / "godot_physics_3d" / "godot_body_pair_3d.cpp"


class CCDTransformCacheContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source = SOURCE.read_text(encoding="utf-8")
        begin = source.index("bool GodotBodyPair3D::_test_ccd(")
        end = source.index("real_t combine_bounce(", begin)
        cls.routine = source[begin:end]

    def test_target_inverse_is_computed_once_before_support_loop(self):
        routine = self.routine
        loop = routine.index("for (int i = 0; i < support_count_A; i++)")
        inversion = "predicted_xform_B.affine_inverse()"
        self.assertEqual(routine.count(inversion), 1)
        self.assertLess(routine.index(inversion), loop)
        self.assertLess(routine.index("const Transform3D predicted_inv_B"), loop)
        self.assertNotIn("affine_inverse()", routine[loop:])

    def test_target_shape_lookup_is_outside_support_loop(self):
        routine = self.routine
        loop = routine.index("for (int i = 0; i < support_count_A; i++)")
        self.assertLess(routine.index("GodotShape3D *shape_B_ptr"), loop)
        self.assertNotIn("p_B->get_shape(p_shape_B)", routine[loop:])
        self.assertIn("shape_B_ptr->intersect_segment", routine[loop:])

    def test_cast_endpoints_share_same_cached_inverse(self):
        routine = self.routine
        self.assertIn("predicted_inv_B.xform(from - motion * 0.1)", routine)
        self.assertIn("predicted_inv_B.xform(to)", routine)
        self.assertIn("predicted_xform_B.xform(segment_hit_local)", routine)

    def test_ccd_stress_workload_is_registered(self):
        import run

        script = (Path(__file__).resolve().parent / "stress.gd").read_text(encoding="utf-8")
        self.assertIn("physics_ccd_3d", run.CASES)
        self.assertIn('"physics_ccd_3d":', script)
        self.assertIn("func _physics_ccd_3d(", script)
        self.assertIn("body.continuous_cd = true", script)
        self.assertIn("await physics_frame", script)


if __name__ == "__main__":
    unittest.main()
