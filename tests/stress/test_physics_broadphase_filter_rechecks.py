"""Source contracts for layer/mask updates on stationary GodotPhysics BVH pairs.

The accompanying physics_filter_toggle_2d/3d workloads exercise real
SceneTree Area/StaticBody overlap membership on a native engine build.
"""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
MODULES = ROOT / "modules"


class PhysicsBroadphaseFilterContracts(unittest.TestCase):
    def test_bvh_filter_recheck_api_in_2d_and_3d(self):
        for dimension in ("2d", "3d"):
            with self.subTest(dimension=dimension):
                source_dir = MODULES / f"godot_physics_{dimension}"
                prefix = f"godot_broad_phase_{dimension}"
                base = (source_dir / f"{prefix}.h").read_text(encoding="utf-8")
                interface = (source_dir / f"{prefix}_bvh.h").read_text(encoding="utf-8")
                implementation = (source_dir / f"{prefix}_bvh.cpp").read_text(encoding="utf-8")
                self.assertIn("virtual void force_collision_check(ID p_id) = 0;", base)
                self.assertIn("virtual void force_collision_check(ID p_id) override;", interface)
                self.assertIn("bvh.force_collision_check(p_id - 1);", implementation)
                self.assertIn("ERR_FAIL_COND(!p_id);", implementation)

    def test_layer_and_mask_setters_skip_unchanged_values(self):
        for dimension in ("2d", "3d"):
            with self.subTest(dimension=dimension):
                header = (
                    MODULES / f"godot_physics_{dimension}" / f"godot_collision_object_{dimension}.h"
                ).read_text(encoding="utf-8")
                for name, value in (("set_collision_mask", "collision_mask"), ("set_collision_layer", "collision_layer")):
                    begin = header.index(f"void {name}(")
                    end = header.index("}", header.index("}", begin) + 1)
                    body = header[begin:end]
                    self.assertIn(f"if ({value} == p_", body)
                    self.assertIn("_collision_filter_changed();", body)
                    self.assertNotIn("_shape_changed();", body)

    def test_only_filter_pairs_are_rechecked_without_shape_rebuilds(self):
        for dimension in ("2d", "3d"):
            with self.subTest(dimension=dimension):
                code = (
                    MODULES / f"godot_physics_{dimension}" / f"godot_collision_object_{dimension}.cpp"
                ).read_text(encoding="utf-8")
                begin = code.index(f"::_collision_filter_changed()")
                end = code.index(f"::_shape_changed()", begin)
                body = code[begin:end]
                self.assertIn("if (space)", body)
                self.assertIn("if (shape.bpid != 0)", body)
                self.assertIn("broadphase->force_collision_check(shape.bpid);", body)
                self.assertIn("_shapes_changed();", body)
                self.assertNotIn("_update_shapes();", body)

    def test_underlying_bvh_forces_full_pair_filter_validation(self):
        code = (ROOT / "core/math/bvh.h").read_text(encoding="utf-8")
        begin = code.index("void force_collision_check(BVHHandle p_handle)")
        end = code.index("bool activate(BVHHandle p_handle", begin)
        self.assertIn("_add_changed_item(p_handle, aabb, false)", code[begin:end])
        self.assertIn("_check_for_collisions(true)", code[begin:end])

    def test_stress_cases_are_registered_and_test_stationary_masks(self):
        runner = (ROOT / "tests/stress/run.py").read_text(encoding="utf-8")
        script = (ROOT / "tests/stress/stress.gd").read_text(encoding="utf-8")
        workload = (ROOT / "tests/stress/physics_filter_toggle.gd").read_text(encoding="utf-8")
        for dimension in ("2d", "3d"):
            case = f"physics_filter_toggle_{dimension}"
            with self.subTest(case=case):
                self.assertIn(f'"{case}"', runner)
                self.assertIn(f'"{case}":', script)
                self.assertIn(f"func run_{dimension}(", workload)
        self.assertIn("area.get_overlapping_bodies()", workload)
        self.assertIn("area.collision_mask = target_mask", workload)
        self.assertNotIn("area.global_position =", workload)


if __name__ == "__main__":
    unittest.main()
