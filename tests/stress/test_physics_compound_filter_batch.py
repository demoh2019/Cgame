"""Source regressions for batched compound-body BVH filter revalidation.

The source contracts detect missing full-check propagation without requiring
a compiled editor. Companion GDScript workloads validate actual pair counts.
"""

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
STRESS = ROOT / "tests/stress"


class CompoundFilterBatchContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.bvh = (ROOT / "core/math/bvh.h").read_text(encoding="utf-8")
        cls.runner = (STRESS / "run.py").read_text(encoding="utf-8")
        cls.dispatcher = (STRESS / "stress.gd").read_text(encoding="utf-8")
        cls.project = (STRESS / "project.godot").read_text(encoding="utf-8")

    def test_pending_full_check_survives_deferred_changes(self):
        code = self.bvh
        self.assertIn("bool _pending_full_pair_check = false;", code)
        self.assertIn("void force_collision_check(uint32_t p_handle, bool p_defer_pairing = false)", code)
        self.assertIn("void force_collision_check(BVHHandle p_handle, bool p_defer_pairing = false)", code)
        self.assertIn("force_collision_check(h, p_defer_pairing);", code)
        self.assertIn("if (p_defer_pairing) {\n\t\t\t\t_pending_full_pair_check = true;", code)
        self.assertIn("const bool full_check = p_full_check || _pending_full_pair_check;", code)
        self.assertIn("_find_leavers(h, abb, full_check);", code)
        self.assertIn("tree.visit_aabb_refs(", code)
        self.assertIn("_pending_full_pair_check = false;", code)

    def test_compound_2d_and_3d_filters_batch_and_flush(self):
        for dimension in ("2d", "3d"):
            with self.subTest(dimension=dimension):
                folder = ROOT / "modules" / f"godot_physics_{dimension}"
                collision = (folder / f"godot_collision_object_{dimension}.cpp").read_text(encoding="utf-8")
                backend = (folder / f"godot_broad_phase_{dimension}_bvh.cpp").read_text(encoding="utf-8")
                tag = dimension.upper()
                name = f"void GodotCollisionObject{tag}::refresh_collision_pairs() {{"
                method = collision.split(name, 1)[1].split("\n}", 1)[0]
                self.assertIn("const bool batch = shapes.size() > 1;", method)
                self.assertIn("broadphase->begin_batch();", method)
                self.assertIn("broadphase->force_collision_check(shape.bpid);", method)
                self.assertIn("broadphase->end_batch();", method)
                self.assertLess(method.index("broadphase->begin_batch();"), method.index("broadphase->force_collision_check(shape.bpid);"))
                self.assertLess(method.index("broadphase->force_collision_check(shape.bpid);"), method.index("broadphase->end_batch();"))
                self.assertIn("bvh.force_collision_check(p_id - 1, batch_depth > 0);", backend)
                self.assertIn("if (--batch_depth == 0) {\n\t\tbvh.flush_pending_pairs();", backend)
                self.assertIn("refresh_collision_pairs();", collision)

    def test_compound_stationary_filter_scenarios_are_registered(self):
        for dimension in ("2d", "3d"):
            with self.subTest(dimension=dimension):
                name = f"physics_compound_filter_batch_{dimension}"
                workload = (STRESS / f"{name}.gd").read_text(encoding="utf-8")
                self.assertIn("32 * mini(scale, 8)", workload)
                for token in (
                    "body_add_shape(mover, shape",
                    "body_set_collision_mask(mover, mask)",
                    "body_set_collision_layer(mover, 0)",
                    "body_set_collision_layer(mover, 1)",
                    "body_add_collision_exception(mover, obstacles[0])",
                    "body_remove_collision_exception(mover, obstacles[0])",
                    "compound_filter_batch_verified",
                ):
                    self.assertIn(token, workload)
                self.assertIn(f'"{name}"', self.runner)
                self.assertIn(f'"{name}":', self.dispatcher)
                self.assertIn(f'{dimension}/physics_engine="GodotPhysics{dimension.upper()}"', self.project)


if __name__ == "__main__":
    unittest.main()
