"""Regression contracts for Jolt-style unchanged static-body transform short-circuit.

This only checks source structure and test coverage. Execute the companion
headless GDScript test with GodotPhysics2D/GodotPhysics3D for runtime validation.
"""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
RUNTIME = ROOT / "tests/stress/physics_static_transform_sleep_regression.gd"
PROXY_RUNTIME = ROOT / "tests/stress/physics_broadphase_aabb_cache_regression.gd"
PROXY_WORKLOAD = ROOT / "tests/stress/physics_proxy_same_aabb.gd"
STRESS = ROOT / "tests/stress/stress.gd"
RUNNER = ROOT / "tests/stress/run.py"


class PhysicsStaticTransformNoop(unittest.TestCase):
    def test_static_set_state_avoids_wake_and_shape_updates(self):
        for dim, type_name in (("2d", "Transform2D"), ("3d", "Transform3D")):
            with self.subTest(dim=dim):
                source = (ROOT / "modules" / f"godot_physics_{dim}" /
                          f"godot_body_{dim}.cpp").read_text(encoding="utf-8")
                class_name = f"GodotBody{dim.upper()}"
                start = source.index(f"void {class_name}::set_state(")
                end = source.index("BODY_STATE_LINEAR_VELOCITY", start)
                code = source[start:end]
                mode = f"PS{dim[0]}DE::BODY_MODE_STATIC"
                self.assertIn(f"else if (mode == {mode})", code)
                static_start = code.index(f"else if (mode == {mode})")
                static_end = code.index("} else {", static_start)
                static = code[static_start:static_end]
                self.assertIn(f"const {type_name} transform = p_variant;", static)
                self.assertIn("if (transform == get_transform()) {", static)
                self.assertIn("break;", static)
                self.assertIn("_set_transform(transform);", static)
                self.assertIn("_set_inv_transform(get_transform().affine_inverse());", static)
                self.assertIn("wakeup_neighbours();", static)
                self.assertLess(
                    static.index("if (transform == get_transform())"),
                    static.index("_set_transform(transform);"),
                )
                self.assertLess(static.index("break;"), static.index("wakeup_neighbours();"))

    def test_kinematic_and_rigid_transform_semantics_unchanged(self):
        for dim in ("2d", "3d"):
            with self.subTest(dim=dim):
                source = (ROOT / "modules" / f"godot_physics_{dim}" /
                          f"godot_body_{dim}.cpp").read_text(encoding="utf-8")
                start = source.index(f"void GodotBody{dim.upper()}::set_state(")
                end = source.index("BODY_STATE_LINEAR_VELOCITY", start)
                code = source[start:end]
                self.assertIn(f"mode == PS{dim[0]}DE::BODY_MODE_KINEMATIC", code)
                self.assertIn("set_active(true);", code)
                self.assertIn("first_time_kinematic = false;", code)
                self.assertIn("t.orthonormalize();", code)
                self.assertIn("_update_transform_dependent();", code)
                self.assertIn("wakeup();", code)

    def test_neighbour_sleep_and_actual_motion_covered_at_runtime(self):
        script = RUNTIME.read_text(encoding="utf-8")
        for dim in ("2D", "3D"):
            self.assertIn(f"PhysicsServer{dim}.joint_make_pin(", script)
            self.assertIn(f"PhysicsServer{dim}.BODY_STATE_SLEEPING, true", script)
            self.assertIn(f"PhysicsServer{dim}.BODY_STATE_TRANSFORM", script)
            self.assertIn(f"PhysicsServer{dim}.free_rid(", script)
        self.assertIn("for i in range(128):", script)
        self.assertIn("identical 2D static transform woke", script)
        self.assertIn("identical 3D static transform woke", script)
        self.assertIn("changed 2D static transform did not wake", script)
        self.assertIn("changed 3D static transform did not wake", script)
        self.assertIn("await physics_frame", script)

    def test_broadphase_and_shape_resize_remain_covered(self):
        runtime = PROXY_RUNTIME.read_text(encoding="utf-8")
        workload = PROXY_WORKLOAD.read_text(encoding="utf-8")
        for dim in ("2D", "3D"):
            self.assertIn(f"PhysicsServer{dim}.shape_set_data(", runtime)
            self.assertIn(f"PhysicsServer{dim}.body_set_state(", runtime)
            self.assertIn(f"PhysicsServer{dim}.body_set_state(", workload)
        self.assertIn("old_hit.is_empty()", runtime)
        self.assertIn("new_hit.is_empty()", runtime)
        self.assertIn('"ns_per_update"', workload)
        runner = RUNNER.read_text(encoding="utf-8")
        cases = STRESS.read_text(encoding="utf-8")
        for dim in ("2d", "3d"):
            name = f"physics_proxy_same_aabb_{dim}"
            self.assertIn(f'"{name}"', runner)
            self.assertIn(f'"{name}":', cases)


if __name__ == "__main__":
    unittest.main()
