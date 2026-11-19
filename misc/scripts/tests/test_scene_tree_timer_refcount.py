"""SceneTree timer hot loop must not acquire a transient Ref for every tick.

A separate native C++ test checks actual behavior/lifetimes when the engine is built.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
TREE = ROOT / "scene/main/scene_tree.cpp"
TESTS = ROOT / "tests/scene/test_timer.cpp"


class SceneTreeTimerRefFastPathTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        src = TREE.read_text(encoding="utf-8")
        begin = src.index("void SceneTree::process_timers(")
        end = src.index("void SceneTree::process_tweens(", begin)
        cls.method = src[begin:end]
        cls.tests = TESTS.read_text(encoding="utf-8")

    def test_borrow_strong_ref_only_during_normal_tick(self):
        self.assertIn("const Ref<SceneTreeTimer> &timer = E->get();", self.method)
        self.assertNotIn("Ref<SceneTreeTimer> timer = E->get();", self.method)

    def test_timeout_keeps_object_alive_while_emitting_signal_and_erasing(self):
        self.assertIn("Ref<SceneTreeTimer> timeout_timer = timer;", self.method)
        self.assertIn('timeout_timer->emit_signal(SNAME("timeout"));', self.method)
        self.assertIn("timers.erase(E);", self.method)
        self.assertLess(
            self.method.index("Ref<SceneTreeTimer> timeout_timer = timer;"),
            self.method.index('timeout_timer->emit_signal(SNAME("timeout"));'),
        )
        self.assertLess(
            self.method.index('timeout_timer->emit_signal(SNAME("timeout"));'),
            self.method.index("timers.erase(E);"),
        )
        self.assertEqual(self.method.count("Ref<SceneTreeTimer> timeout_timer = timer;"), 1)

    def test_physics_and_pause_filter_unchanged(self):
        self.assertIn("(paused && !timer->is_process_always())", self.method)
        self.assertIn("(timer->is_process_in_physics() != p_physics_frame)", self.method)
        self.assertIn("time_left -= timer->is_ignoring_time_scale() ? unscaled_delta : p_delta;", self.method)

    def test_native_lifetime_and_frame_mode_regressions_exist(self):
        for case in (
            "Active timers hold stable references across frames",
            "Timeout emitted exactly once with retained handle",
            "Physics timers ignore idle ticks",
        ):
            self.assertIn("[SceneTreeTimerRefFastPath] " + case, self.tests)
        self.assertIn("timers.reserve(128);", self.tests)
        self.assertIn("timer->get_reference_count()", self.tests)


if __name__ == "__main__":
    unittest.main()
