"""Source contracts: collision filter changes must re-evaluate stationary BVH pairs.

Run with python3 -m unittest discover -s tests/stress -p 'test_*.py'.
Native behavior remains covered by the separate Area/RigidBody runtime scenario.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]

class PhysicsBroadphaseMaskContracts(unittest.TestCase):
    def test_broadphase_exposes_full_recheck(self):
        for dimension in ("2d", "3d"):
            with self.subTest(dimension=dimension):
                prefix = ROOT / "modules" / f"godot_physics_{dimension}" / f"godot_broad_phase_{dimension}"
                base = prefix.with_suffix(".h").read_text(encoding="utf-8")
                impl_header = (prefix.parent / (prefix.name + "_bvh.h")).read_text(encoding="utf-8")
                impl = (prefix.parent / (prefix.name + "_bvh.cpp")).read_text(encoding="utf-8")
                self.assertIn("virtual void force_collision_check(ID p_id) = 0;", base)
                self.assertIn("virtual void force_collision_check(ID p_id) override;", impl_header)
                self.assertIn("bvh.force_collision_check(p_id - 1);", impl)

    def test_mask_and_layer_changes_do_not_rebuild_aabbs(self):
        for dimension in ("2d", "3d"):
            with self.subTest(dimension=dimension):
                prefix = ROOT / "modules" / f"godot_physics_{dimension}" / f"godot_collision_object_{dimension}"
                header = prefix.with_suffix(".h").read_text(encoding="utf-8")
                impl = prefix.with_suffix(".cpp").read_text(encoding="utf-8")
                self.assertIn("collision_mask == p_mask", header)
                self.assertIn("collision_layer == p_layer", header)
                self.assertEqual(header.count("_collision_filter_changed();"), 3)
                begin = impl.index("::_collision_filter_changed()")
                end = impl.index("::_shape_changed()", begin)
                routine = impl[begin:end]
                self.assertIn("broadphase->force_collision_check(shape.bpid);", routine)
                self.assertIn("_shapes_changed();", routine)
                self.assertNotIn("_update_shapes();", routine)

    def test_bvh_full_recheck_handles_both_old_and_new_pairs(self):
        bvh = (ROOT / "core/math/bvh.h").read_text(encoding="utf-8")
        begin = bvh.index("void force_collision_check(BVHHandle p_handle)")
        end = bvh.index("bool activate(BVHHandle p_handle", begin)
        section = bvh[begin:end]
        self.assertIn("_add_changed_item(p_handle, aabb, false)", section)
        self.assertIn("_check_for_collisions(true)", section)

if __name__ == "__main__":
    unittest.main()
