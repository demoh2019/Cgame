"""Jolt: avoid OptimizeBroadPhase for pending bodies that were never inserted.

The regression tests both the paused-editor create/destroy path and the
ordinary inserted-body removal path. Static checks are not a substitute for
the native runtime stress test or timing comparisons.
"""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
SPACE_CPP = ROOT / "modules/jolt_physics/spaces/jolt_space_3d.cpp"
STRESS_GD = ROOT / "tests/stress/physics_jolt_pending_broadphase_regression.gd"


def should_optimize(was_pending: bool, server_active: bool, bodies_after: int) -> bool:
    """Model the narrowly guarded Jolt editor broadphase cleanup."""
    return not was_pending and not server_active and bodies_after <= 1


class JoltPendingBroadphaseTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source = SPACE_CPP.read_text(encoding="utf-8")
        cls.remove = source.split(
            "void JoltSpace3D::remove_object(const JPH::BodyID &p_jolt_id) {", 1
        )[1].split("void JoltSpace3D::flush_pending_objects()", 1)[0]

    def test_skip_broadphase_rebuild_only_for_pending_deletes(self):
        code = self.remove
        self.assertIn("const bool was_pending = _pending_erase(", code)
        self.assertIn("pending_objects_sleeping, pending_sleeping_indices", code)
        self.assertIn("pending_objects_awake, pending_awake_indices", code)
        self.assertIn("if (!was_pending) {", code)
        self.assertIn("body_iface.RemoveBody(p_jolt_id);", code)
        self.assertIn("body_iface.DestroyBody(p_jolt_id);", code)
        self.assertIn(
            "if (!was_pending && !JoltPhysicsServer3D::get_singleton()->is_active() "
            "&& physics_system->GetNumBodies() <= 1) {",
            code,
        )
        self.assertIn("physics_system->OptimizeBroadPhase();", code)
        self.assertEqual(code.count("OptimizeBroadPhase();"), 1)

    def test_removal_precedes_destruction_and_optional_optimization(self):
        code = self.remove
        self.assertLess(code.index("body_iface.RemoveBody("), code.index("body_iface.DestroyBody("))
        self.assertLess(code.index("body_iface.DestroyBody("), code.index("physics_system->OptimizeBroadPhase("))

    def test_pending_bodies_never_trigger_rebuild(self):
        for server_active in (True, False):
            for body_count in (0, 1, 2, 10240):
                self.assertFalse(should_optimize(True, server_active, body_count))

    def test_inserted_bodies_preserve_old_cleanup_conditions(self):
        for active, bodies, expected in (
            (False, 0, True),
            (False, 1, True),
            (False, 2, False),
            (False, 4096, False),
            (True, 0, False),
            (True, 1, False),
        ):
            with self.subTest(server_active=active, remaining_bodies=bodies):
                self.assertEqual(should_optimize(False, active, bodies), expected)

    def test_stress_covers_paused_scene_churn_and_inserted_deletes(self):
        gd = STRESS_GD.read_text(encoding="utf-8")
        self.assertIn("const SINGLE_CHURN := 2048", gd)
        self.assertIn("const BATCH_SIZE := 256", gd)
        self.assertIn("const BATCH_WAVES := 4", gd)
        self.assertIn("PhysicsServer3D.set_active(false)", gd)
        self.assertIn("PhysicsServer3D.set_active(true)", gd)
        self.assertIn("PhysicsServer3D.free_rid(body)", gd)
        self.assertIn("await physics_frame", gd)
        self.assertIn("active_before_removal", gd)
        self.assertIn("Jolt pending broadphase regression passed.", gd)
        self.assertIn("JOLT_PENDING_BROADPHASE_RESULT:", gd)


if __name__ == "__main__":
    unittest.main()
