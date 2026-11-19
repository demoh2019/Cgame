"""Source contracts and conservative geometry for clipped shape-cast pruning.

These tests complement but do not replace the native Godot test binary and
tests/stress/physics_shapecast_clipped_aabb_regression.gd.
"""
from pathlib import Path
import random
import unittest


ROOT = Path(__file__).resolve().parents[2]
HEADER = ROOT / "servers/physics_cast_motion_pruning.h"
SPACE_2D = ROOT / "modules/godot_physics_2d/godot_space_2d.cpp"
SPACE_3D = ROOT / "modules/godot_physics_3d/godot_space_3d.cpp"
STRESS = ROOT / "tests/stress/physics_shapecast_clipped_aabb_regression.gd"


def overlaps(bounds1, bounds2):
    return all(a0 <= b1 and b0 <= a1 for (a0, a1), (b0, b1) in zip(bounds1, bounds2))


def clipped_bounds(box, delta, fraction, margin):
    return tuple(
        (min(lo, lo + movement * fraction) - max(margin, 0),
         max(hi, hi + movement * fraction) + max(margin, 0))
        for (lo, hi), movement in zip(box, delta)
    )


class ClippedShapeCastTests(unittest.TestCase):
    def test_pruning_is_conservative_at_random_intermediate_times(self):
        # A linearly translated shape must fit the union of its initial and
        # clipped-ending AABBs at every intermediate time.
        rng = random.Random(4078)
        for dims in (2, 3):
            for _ in range(2000):
                box = []
                motion = []
                for _axis in range(dims):
                    lower = rng.uniform(-100, 100)
                    box.append((lower, lower + rng.uniform(0.05, 10)))
                    motion.append(rng.uniform(-100, 100))
                fraction = rng.random()
                margin = rng.uniform(-0.1, 2.0)
                clipped = clipped_bounds(box, motion, fraction, margin)
                for point_fraction in (0.0, 0.25, 0.5, 0.75, 1.0):
                    t = fraction * point_fraction
                    intermediate = [(lo + m * t, hi + m * t)
                                    for (lo, hi), m in zip(box, motion)]
                    for (lo, hi), (bound_lo, bound_hi) in zip(intermediate, clipped):
                        self.assertLessEqual(bound_lo - 1e-9, lo)
                        self.assertGreaterEqual(bound_hi + 1e-9, hi)
                # Candidates strictly outside the clipped bounds cannot
                # touch the moving shape before the clipped time fraction.
                far = tuple((hi + 10.0, hi + 11.0) for _, hi in clipped)
                self.assertFalse(overlaps(clipped, far))

    def test_inline_helper_is_reused_for_both_dimensions(self):
        header = HEADER.read_text(encoding="utf-8")
        self.assertIn("godot_physics_cast_motion_clipped_aabb", header)
        self.assertIn("p_motion * p_max_fraction", header)
        self.assertIn("MAX(real_t(0.0), p_margin)", header)
        self.assertIn("CMP_EPSILON", header)

    def test_2d_prunes_after_earliest_hit_without_changing_solver_iterations(self):
        text = SPACE_2D.read_text(encoding="utf-8")
        a = text.index("bool GodotPhysicsDirectSpaceState2D::cast_motion(")
        b = text.index("bool GodotPhysicsDirectSpaceState2D::collide_shape(", a)
        code = text[a:b]
        self.assertIn("const Rect2 start_aabb =", code)
        self.assertIn("data.best_unsafe < 1.0", code)
        self.assertIn("data.clipped_aabb.intersects(p_object->get_shape_aabb(p_shape), true)", code)
        self.assertLess(code.index("data.clipped_aabb.intersects"), code.index("GodotCollisionSolver2D::solve("))
        self.assertIn("data.clipped_aabb = godot_physics_cast_motion_clipped_aabb(", code)
        self.assertEqual(code.count("for (int j = 0; j < 8; j++)"), 1)
        self.assertIn("data.params.exclude.has(", code)
        self.assertIn("_can_collide_with(", code)

    def test_3d_prunes_before_gjk_without_changing_rest_info_selection(self):
        text = SPACE_3D.read_text(encoding="utf-8")
        a = text.index("bool GodotPhysicsDirectSpaceState3D::cast_motion(")
        b = text.index("bool GodotPhysicsDirectSpaceState3D::collide_shape(", a)
        code = text[a:b]
        self.assertIn("const AABB start_aabb =", code)
        self.assertIn("data.best_unsafe < 1.0", code)
        self.assertIn("data.clipped_aabb.intersects(p_object->get_shape_aabb(p_shape))", code)
        self.assertLess(code.index("data.clipped_aabb.intersects"), code.index("GodotCollisionSolver3D::solve_distance("))
        self.assertIn("data.clipped_aabb = godot_physics_cast_motion_clipped_aabb(", code)
        self.assertIn("data.motion_shape.motion = data.full_motion;", code)
        self.assertEqual(code.count("for (int j = 0; j < 8; j++)"), 1)
        self.assertIn("data.info->collider_id", code)
        self.assertIn("data.info->normal", code)
        self.assertIn("data.params.exclude.has(", code)

    def test_headless_regression_has_far_objects_and_exclusions(self):
        text = STRESS.read_text(encoding="utf-8")
        self.assertIn("const FAR_COUNT := 4096", text)
        self.assertIn("for _i in range(REPEATS)", text)
        self.assertIn("params.exclude = [bodies[0]]", text)
        self.assertIn("params.collision_mask = 2", text)
        self.assertIn("func _check_2d()", text)
        self.assertIn("func _check_3d()", text)


if __name__ == "__main__":
    unittest.main()
