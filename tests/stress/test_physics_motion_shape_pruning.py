"""Source-contract regression for tight streaming motion BVH queries.

These assertions inspect C++ integration and test registration without needing
an engine binary. They do NOT replace compiling Godot or running physics tests.
"""

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SPACE = ROOT / "modules"
STRESS = ROOT / "tests/stress"


class MotionShapePruningContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = {
            d: (SPACE / f"godot_physics_{d}/godot_space_{d}.cpp").read_text(encoding="utf-8")
            for d in ("2d", "3d")
        }
        cls.headers = {
            d: (SPACE / f"godot_physics_{d}/godot_space_{d}.h").read_text(encoding="utf-8")
            for d in ("2d", "3d")
        }
        cls.workloads = {
            d: (STRESS / f"physics_motion_exclusions_{d}.gd").read_text(encoding="utf-8")
            for d in ("2d", "3d")
        }

    def test_three_narrowphase_stages_stream_tight_shape_aabbs(self):
        for dimension in ("2d", "3d"):
            with self.subTest(dimension=dimension):
                cpp = self.source[dimension]
                motion = cpp.split(f"bool GodotSpace{dimension.upper()}::test_body_motion(", 1)[1]
                motion = motion.split("// Assumes a valid collision pair", 1)[0]
                self.assertEqual(motion.count("_visit_motion_candidates(p_body, "), 3)
                for bound in ("shape_query_aabb", "shape_motion_aabb", "shape_rest_aabb"):
                    self.assertIn(f"_visit_motion_candidates(p_body, {bound}, p_parameters", motion)
                self.assertIn("shape_motion_aabb = shape_motion_aabb.merge(shape_end_aabb);", motion)
                self.assertIn("shape_end_aabb.position += p_parameters.motion;", motion)
                self.assertIn("body_shape_xform.xform(body_shape->get_aabb()).grow(margin)", motion)
                self.assertNotIn("_visit_motion_candidates(p_body, body_aabb", motion)
                self.assertNotIn("_visit_motion_candidates(p_body, motion_aabb", motion)
                self.assertNotIn("Rect2 motion_aabb = body_aabb;", motion)
                self.assertNotIn("AABB motion_aabb = body_aabb;", motion)

    def test_early_collision_filters_and_no_candidate_array(self):
        for dimension in ("2d", "3d"):
            with self.subTest(dimension=dimension):
                cpp = self.source[dimension]
                header = self.headers[dimension]
                self.assertIn("query.params.exclude_bodies.has(p_object->get_self())", cpp)
                self.assertIn("query.params.exclude_objects.has(p_object->get_instance_id())", cpp)
                self.assertIn("query.body->collides_with(other)", cpp)
                self.assertNotIn("intersection_query_results", header)
                self.assertNotIn("INTERSECTION_QUERY_MAX", header)

    def test_3d_concave_narrowphase_receives_tight_sweep_hint(self):
        cpp = self.source["3d"]
        self.assertEqual(cpp.count(", shape_motion_aabb, &sep_axis)"), 2)
        self.assertEqual(cpp.count(", shape_motion_aabb, &sep)"), 1)
        self.assertNotIn(", motion_aabb, &sep_axis)", cpp)
        self.assertNotIn(", motion_aabb, &sep)", cpp)

    def test_dense_sparse_offset_rotated_and_compound_regressions(self):
        project = (STRESS / "project.godot").read_text(encoding="utf-8")
        runner = (STRESS / "run.py").read_text(encoding="utf-8")
        stress = (STRESS / "stress.gd").read_text(encoding="utf-8")
        for dimension in ("2d", "3d"):
            with self.subTest(dimension=dimension):
                script = self.workloads[dimension]
                self.assertIn("2048 + 128 * mini(scale, 8)", script)
                for token in (
                    "query.exclude_bodies = excluded_bodies",
                    "dense_nearest_hit_verified",
                    "compound_nearest_hit_verified",
                    "gap_query_ms",
                    "offset_shape_hit_verified",
                    "rotated_compound_hit_verified",
                ):
                    self.assertIn(token, script)
                self.assertIn(
                    f'{dimension}/physics_engine="GodotPhysics{dimension.upper()}"',
                    project,
                )
                self.assertIn(f'"physics_motion_exclusions_{dimension}"', runner)
                self.assertIn(f'"physics_motion_exclusions_{dimension}"', stress)


if __name__ == "__main__":
    unittest.main()
