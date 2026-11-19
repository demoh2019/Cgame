"""Source contracts and reference model for early-filtered 2D body motion.

The pure reference checks don't substitute for the headless Godot stress
workload, C++ build, or runtime collision correctness.
"""
from __future__ import annotations

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
SPACE_CPP = ROOT / "modules/godot_physics_2d/godot_space_2d.cpp"
SPACE_H = ROOT / "modules/godot_physics_2d/godot_space_2d.h"
RUNNER = ROOT / "tests/stress/run.py"
WORKLOAD = ROOT / "tests/stress/stress.gd"
SCENARIO = ROOT / "tests/stress/physics_motion_filter_overflow_2d.gd"


def early_filter(proxies: list[tuple[str, bool]], capacity: int) -> list[str]:
    """Mirrors early rejection of areas and noncolliding body proxies."""
    accepted = []
    for proxy_id, collision_allowed in proxies:
        if not collision_allowed:
            continue
        accepted.append(proxy_id)
        if len(accepted) == capacity:
            break
    return accepted


class PhysicsMotion2DEarlyFilterTests(unittest.TestCase):
    def test_filtered_candidates_do_not_consume_scratch_slots(self):
        proxies = [(f"area{i}", False) for i in range(4096)]
        proxies += [(f"excluded{i}", False) for i in range(128)]
        proxies.append(("obstacle", True))
        self.assertEqual(early_filter(proxies, 2048), ["obstacle"])
        self.assertEqual(early_filter(proxies, 1), ["obstacle"])

    def test_capacity_remains_bounded_after_acceptance(self):
        proxies = [(f"body{i}", True) for i in range(4096)]
        self.assertEqual(len(early_filter(proxies, 2048)), 2048)

    def test_body_motion_uses_early_filtering_at_all_three_call_sites(self):
        cpp = SPACE_CPP.read_text(encoding="utf-8")
        header = SPACE_H.read_text(encoding="utf-8")
        begin = cpp.index("int GodotSpace2D::_cull_aabb_for_body(")
        end = cpp.index("bool GodotSpace2D::test_body_motion(", begin)
        cull = cpp[begin:end]
        motion = cpp[end:cpp.index("void *GodotSpace2D::_broadphase_pair(", end)]
        self.assertIn("broadphase->visit_aabb(p_aabb, visitor, &data);", cull)
        self.assertNotIn("broadphase->cull_aabb(", cull)
        self.assertIn("query.params.exclude_bodies.has(", cull)
        self.assertIn("query.params.exclude_objects.has(", cull)
        self.assertIn("p_object->get_type() != GodotCollisionObject2D::TYPE_BODY", cull)
        self.assertIn("!query.body->collides_with(other)", cull)
        self.assertIn("other->has_exception(query.body->get_self())", cull)
        self.assertIn("query.body->has_exception(other->get_self())", cull)
        self.assertLess(cull.index("if (p_object == query.body"), cull.index("query.results[query.count] = p_object;"))
        self.assertLess(cull.index("query.params.exclude_bodies.has("), cull.index("query.results[query.count] = p_object;"))
        self.assertIn("return query.count < query.capacity;", cull)
        self.assertEqual(motion.count("_cull_aabb_for_body(p_body, body_aabb, p_parameters)"), 2)
        self.assertEqual(motion.count("_cull_aabb_for_body(p_body, motion_aabb, p_parameters)"), 1)
        self.assertIn("const PS2DT::MotionParameters &p_parameters", header)

    def test_stationary_motion_guard(self):
        cpp = SPACE_CPP.read_text(encoding="utf-8")
        self.assertIn("motion_length > 0.0 ? p_parameters.motion / motion_length : Vector2()", cpp)

    def test_load_test_is_registered(self):
        runner = RUNNER.read_text(encoding="utf-8")
        workload = WORKLOAD.read_text(encoding="utf-8")
        scenario = SCENARIO.read_text(encoding="utf-8")
        self.assertIn('"physics_motion_filter_overflow_2d"', runner)
        self.assertIn('"physics_motion_filter_overflow_2d"', workload)
        self.assertIn("MotionFilterOverflow2D.new().run(self, scale, frames)", workload)
        self.assertIn("PhysicsServer2D.body_test_motion(", scenario)
        self.assertIn("body_remove_collision_exception(", scenario)
        self.assertIn("Vector2.ZERO", scenario)


if __name__ == "__main__":
    unittest.main()
