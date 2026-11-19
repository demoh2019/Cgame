"""Contracts for exact 2D BVH point query forwarding and filtering.

Native C++/GDScript tests must also run for runtime correctness.
"""
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "modules/godot_physics_2d/godot_broad_phase_2d.h"
IMPL_H = ROOT / "modules/godot_physics_2d/godot_broad_phase_2d_bvh.h"
IMPL_CPP = ROOT / "modules/godot_physics_2d/godot_broad_phase_2d_bvh.cpp"
SPACE = ROOT / "modules/godot_physics_2d/godot_space_2d.cpp"
NATIVE = ROOT / "tests/core/math/test_bvh_2d_exact_point.cpp"
STRESS = ROOT / "tests/stress/physics_2d_exact_point_bvh_regression.gd"


class Physics2DExactPointTests(unittest.TestCase):
    def test_2d_broadphase_has_exact_bvh_point_visitor(self):
        base = BASE.read_text(encoding="utf-8")
        impl_h = IMPL_H.read_text(encoding="utf-8")
        impl_cpp = IMPL_CPP.read_text(encoding="utf-8")
        signature = "visit_point(const Vector2 &p_point, QueryVisitor p_visitor, void *p_userdata)"
        self.assertIn(signature + " = 0;", base)
        self.assertIn(signature + " override;", impl_h)
        self.assertIn("void GodotBroadPhase2DBVH::" + signature + " {", impl_cpp)
        self.assertIn("bvh.visit_point(p_point, p_visitor, p_userdata);", impl_cpp)

    def test_direct_2d_point_query_uses_exact_bvh_without_epsilon_box(self):
        space = SPACE.read_text(encoding="utf-8")
        start = space.index("int GodotPhysicsDirectSpaceState2D::intersect_point(")
        end = space.index("bool GodotPhysicsDirectSpaceState2D::intersect_ray(", start)
        code = space[start:end]
        self.assertIn("space->broadphase->visit_point(p_parameters.position, visitor, &query);", code)
        self.assertNotIn("visit_aabb(", code)
        self.assertNotIn("query_aabb", code)
        self.assertIn("_can_collide_with(", code)
        self.assertIn("data.params.exclude.has(", code)
        self.assertIn("data.params.pick_point", code)
        self.assertIn("p_object->get_canvas_instance_id()", code)
        self.assertIn("shape->contains_point(local_point)", code)
        self.assertIn("return data.count < data.max_results;", code)

    def test_native_compares_epsilon_aabb_against_exact_point(self):
        code = NATIVE.read_text(encoding="utf-8")
        self.assertIn("DISTRACTORS = 4096", code)
        self.assertIn("tree.visit_aabb(old_query, collect, &old_epsilon)", code)
        self.assertIn("tree.visit_point(Vector2(), collect, &exact)", code)
        self.assertIn("CHECK(exact.candidates == 1)", code)
        self.assertIn("CHECK(old_epsilon.candidates == DISTRACTORS + 1)", code)
        self.assertIn("early_stop.stop_after = 1", code)

    def test_engine_regression_covers_filters_and_shape_updates(self):
        code = STRESS.read_text(encoding="utf-8")
        self.assertIn("const DECOYS := 4096", code)
        self.assertIn("missed != 0", code)
        self.assertIn("query.collision_mask = 2", code)
        self.assertIn("query.exclude = exclude", code)
        self.assertIn("body_set_shape_transform(target", code)
        self.assertIn("body_set_state(target", code)
        self.assertIn("old_point_empty", code)


if __name__ == "__main__":
    unittest.main()
