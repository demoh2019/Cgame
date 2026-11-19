"""Static regression contracts for avoiding redundant physics BVH updates.

Companion runtime test: physics_broadphase_aabb_cache_regression.gd
The Python contracts don't replace running the Godot physics integration test.
"""

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
RUNTIME = ROOT / "tests/stress/physics_broadphase_aabb_cache_regression.gd"
STRESS = ROOT / "tests/stress/stress.gd"
RUNNER = ROOT / "tests/stress/run.py"


class PhysicsBroadphaseAABBCacheTests(unittest.TestCase):
    def test_both_2d_and_3d_skip_identical_proxy_bounds(self):
        for dim, bounds_type in (("2d", "Rect2"), ("3d", "AABB")):
            with self.subTest(dimension=dim):
                path = ROOT / "modules" / f"godot_physics_{dim}" / f"godot_collision_object_{dim}.cpp"
                source = path.read_text(encoding="utf-8")
                methods = ("_update_shapes()", "_update_shapes_with_motion(")
                for i, method in enumerate(methods):
                    marker = f"void GodotCollisionObject{dim.upper()}::{method}"
                    if dim == "2d":
                        marker = f"void GodotCollisionObject2D::{method}"
                    else:
                        marker = f"void GodotCollisionObject3D::{method}"
                    begin = source.index(marker)
                    end = source.index("\n}\n", begin)
                    code = source[begin:end]
                    with self.subTest(method=method):
                        self.assertIn(f"{bounds_type} shape_aabb =", code)
                        self.assertIn("const bool aabb_changed = s.aabb_cache != shape_aabb;", code)
                        self.assertIn("s.aabb_cache = shape_aabb;", code)
                        self.assertIn("} else if (aabb_changed) {", code)
                        self.assertIn("space->get_broadphase()->move(s.bpid, shape_aabb);", code)
                        self.assertLess(code.index("const bool aabb_changed"), code.index("s.aabb_cache = shape_aabb;"))
                        self.assertLess(code.index("s.aabb_cache = shape_aabb;"), code.index("} else if (aabb_changed) {"))
                        self.assertIn("if (s.bpid == 0) {", code)
                        self.assertIn("flush_pending_pairs();", code)
                        if i == 1:
                            self.assertIn("p_motion", code)
                if dim == "3d":
                    self.assertEqual(source.count("s.area_cache = "), 1)

    def test_runtime_regression_checks_noop_and_real_motion(self):
        code = RUNTIME.read_text(encoding="utf-8")
        self.assertIn("PhysicsServer2D.body_set_state(", code)
        self.assertIn("PhysicsServer3D.body_set_state(", code)
        self.assertIn("PhysicsRayQueryParameters2D.create(", code)
        self.assertIn("PhysicsRayQueryParameters3D.create(", code)
        self.assertIn("await physics_frame", code)
        self.assertIn("old_hit.is_empty()", code)
        self.assertIn("new_hit.is_empty()", code)

    def test_stationary_proxy_stress_registered_for_both_dimensions(self):
        runner = RUNNER.read_text(encoding="utf-8")
        script = STRESS.read_text(encoding="utf-8")
        for dimension in ("2d", "3d"):
            name = f"physics_proxy_same_aabb_{dimension}"
            self.assertIn(f'"{name}"', runner)
            self.assertIn(f'"{name}":', script)
            self.assertIn(f"func _{name}(scale: int, frames: int)", script)
            self.assertIn(f"return await _{name}(scale, frames)", script)


if __name__ == "__main__":
    unittest.main()
