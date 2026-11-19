"""Static contracts for Jolt's bounded pending BodyID buffer reuse.

These tests complement (not replace) the native 3D spawn/churn stress.
"""

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPACE = ROOT / "modules/jolt_physics/spaces/jolt_space_3d.cpp"
STRESS = ROOT / "tests/stress/physics_pending_reuse_stress.gd"


class JoltPendingBufferReuseTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        code = SPACE.read_text(encoding="utf-8")
        cls.flush = code.split("void JoltSpace3D::flush_pending_objects() {", 1)[1].split(
            "\nvoid JoltSpace3D::set_is_object_sleeping(", 1
        )[0]

    def test_cached_body_id_capacity_is_bounded(self):
        self.assertIn("MAX_RETAINED_PENDING_BODY_IDS = 4096", SPACE.read_text(encoding="utf-8"))
        for suffix in ("sleeping", "awake"):
            with self.subTest(queue=suffix):
                var = "pending_objects_" + suffix
                expected = f"""if ({var}.get_capacity() > MAX_RETAINED_PENDING_BODY_IDS) {{
\t\t\t{var}.reset();
\t\t}} else {{
\t\t\t{var}.clear();
\t\t}}"""
                self.assertIn(expected, self.flush)

    def test_clearing_pending_index_remains_mandatory(self):
        for suffix in ("sleeping", "awake"):
            self.assertIn(
                f"pending_{suffix}_indices = HashMap<uint32_t, uint32_t>();",
                self.flush,
            )

    def test_flush_still_batches_jolt_additions(self):
        self.assertEqual(self.flush.count("AddBodiesPrepare("), 2)
        self.assertEqual(self.flush.count("AddBodiesFinalize("), 2)
        self.assertIn("JPH::EActivation::DontActivate", self.flush)
        self.assertIn("JPH::EActivation::Activate", self.flush)

    def test_real_churn_workload_exercises_repeated_flush(self):
        script = STRESS.read_text(encoding="utf-8")
        self.assertIn("const COUNT := 512", script)
        self.assertIn("const ROUNDS := 32", script)
        self.assertIn("PhysicsServer3D.body_set_space(body, space)", script)
        self.assertGreaterEqual(script.count("await physics_frame"), 2)
        self.assertIn("PHYSICS_PENDING_REUSE_RESULT:", script)


if __name__ == "__main__":
    unittest.main()
