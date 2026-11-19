"""Source and geometric contracts for 3D shape query collision margin.

This guards broadphase/narrowphase consistency but does not replace the
headless native Godot regression in physics_intersect_shape_margin_3d_regression.gd.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPACE = ROOT / "modules/godot_physics_3d/godot_space_3d.cpp"
SOLVER = ROOT / "modules/godot_physics_3d/godot_collision_solver_3d.cpp"
SCENARIO = ROOT / "tests/stress/physics_intersect_shape_margin_3d_regression.gd"


def overlap(a_min, a_max, b_min, b_max):
    return a_min <= b_max and b_min <= a_max


class ShapeMarginBroadphaseTests(unittest.TestCase):
    def test_static_margin_consistency(self):
        space = SPACE.read_text(encoding="utf-8")
        a = space.index("int GodotPhysicsDirectSpaceState3D::intersect_shape(")
        b = space.index("bool GodotPhysicsDirectSpaceState3D::cast_motion(", a)
        method = space[a:b]
        self.assertIn("p_parameters.transform.xform(shape->get_aabb()).grow(MAX(p_parameters.margin, real_t(0.0)))", method)
        self.assertIn("data.params.margin, 0)", method)
        self.assertIn("space->broadphase->visit_aabb(aabb, visitor, &query)", method)
        self.assertLess(method.index("grow(MAX(p_parameters.margin"), method.index("visit_aabb(aabb, visitor"))

    def test_sat_solver_handles_margin(self):
        solver = SOLVER.read_text(encoding="utf-8")
        self.assertIn("return collision_solver(p_shape_A, p_transform_A, p_shape_B", solver)
        self.assertIn("r_sep_axis, p_margin_A, p_margin_B)", solver)

    def test_conservative_bounds_include_margin_only_overlaps(self):
        # Radius 1 spheres centered at x=0 and x=2.1 have a 0.1 gap.
        query_left, query_right = -1.0, 1.0
        other_left, other_right = 1.1, 3.1
        self.assertFalse(overlap(query_left, query_right, other_left, other_right))
        self.assertTrue(overlap(query_left - 0.25, query_right + 0.25, other_left, other_right))
        # A 0.25 query margin must not reach a sphere at x=2.5.
        self.assertFalse(overlap(query_left - 0.25, query_right + 0.25, 1.5, 3.5))

    def test_headless_regression_covers_masks_exclusions_and_far_shapes(self):
        script = SCENARIO.read_text(encoding="utf-8")
        self.assertIn("without_margin.is_empty()", script)
        self.assertIn("within_margin.size() == 1", script)
        self.assertIn("wrong_layer.is_empty()", script)
        self.assertIn("excluded_result.is_empty()", script)
        self.assertIn("outside_margin.is_empty()", script)


if __name__ == "__main__":
    unittest.main()
