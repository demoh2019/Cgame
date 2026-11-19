"""Source-level regression for streaming BVH broadphase pair generation.

Source contracts run without a compiled engine. The companion GDScript stress
cases verify runtime pairing, layer changes and reinsertion in GodotPhysics.
"""

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
STRESS = ROOT / "tests/stress"


class BVHStreamingPairContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manager = (ROOT / "core/math/bvh.h").read_text(encoding="utf-8")
        cls.cull = (ROOT / "core/math/bvh_cull.inc").read_text(encoding="utf-8")
        cls.runner = (STRESS / "run.py").read_text(encoding="utf-8")
        cls.dispatcher = (STRESS / "stress.gd").read_text(encoding="utf-8")
        cls.project = (STRESS / "project.godot").read_text(encoding="utf-8")

    def test_pair_generation_has_no_candidate_vector(self):
        start = self.manager.index("void _check_for_collisions(bool p_full_check = false)")
        end = self.manager.index("\npublic:\n\tvoid item_get_AABB(", start)
        body = self.manager[start:end]
        self.assertIn("tree.visit_aabb_refs(", body)
        self.assertIn("_find_leavers(h, abb, p_full_check);", body)
        self.assertIn("_collide(query.changed, candidate);", body)
        self.assertIn("_reset();", body)
        self.assertIn("const BOUNDS expanded_aabb =", body)
        self.assertNotIn("tree.cull_aabb(", body)
        self.assertNotIn("for (const uint32_t ref_id : tree._cull_hits)", body)
        self.assertNotIn("params.result_max = INT_MAX", body)

    def test_reference_id_visitor_retains_filters_and_early_exit(self):
        self.assertIn("using RefQueryVisitor = bool (*)(uint32_t, void *);", self.cull)
        self.assertIn("bool visit_aabb_refs(", self.cull)
        self.assertIn("_visit_aabb_iterative<true>(", self.cull)
        self.assertIn("_visit_aabb_iterative<false>(", self.cull)
        self.assertIn("if constexpr (RETURN_REF_IDS)", self.cull)
        self.assertIn("p_ref_visitor(ref_id, p_userdata)", self.cull)
        self.assertIn("USER_CULL_TEST_FUNCTION::user_cull_check(p_tester, extra.userdata)", self.cull)
        self.assertIn("if (!(p_tree_collision_mask & (uint32_t(1) << tree_index)))", self.cull)
        self.assertIn("if (!p_ref_visitor(ref_id, p_userdata)) {\n\t\t\t\t\t\treturn false;", self.cull)

    def test_dense_pair_scenarios_and_backend_selection(self):
        for d in ("2d", "3d"):
            with self.subTest(dimension=d):
                name = f"physics_bvh_streaming_{d}"
                script = (STRESS / f"{name}.gd").read_text(encoding="utf-8")
                for token in (
                    "2048 + 128 * mini(scale, 8)",
                    "INFO_COLLISION_PAIRS",
                    "body_set_collision_mask(mover, new_mask)",
                    "body_set_space(mover, RID())",
                    "pair_rebuild_verified",
                ):
                    self.assertIn(token, script)
                self.assertIn(f'"{name}"', self.runner)
                self.assertIn(f'"{name}":', self.dispatcher)
                self.assertIn(f'{d}/physics_engine="GodotPhysics{d.upper()}"', self.project)


if __name__ == "__main__":
    unittest.main()
