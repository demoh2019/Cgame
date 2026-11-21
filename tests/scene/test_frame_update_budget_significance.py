"""Static source contracts and deterministic model for significance-weighted frame budgets.

Not a substitute for compiling Godot or running the GDScript/native test suites.
"""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CPP = ROOT / "modules/frame_update_budget/frame_update_budget.cpp"
HEADER = ROOT / "modules/frame_update_budget/frame_update_budget.h"
GDSCRIPT = ROOT / "game/scripts/client/ambient_tick_budget.gd"
GAME = ROOT / "game/scripts/client/online_main.gd"
TEST = ROOT / "game/tests/test_ambient_tick_budget.gd"


class TestSignificanceBudget(unittest.TestCase):
    def test_native_api_and_bounded_forecast(self):
        cpp = CPP.read_text(encoding="utf-8")
        header = HEADER.read_text(encoding="utf-8")
        for item in (
            'D_METHOD("set_lane_importance"',
            'D_METHOD("get_lane_importance"',
            'D_METHOD("get_lane_estimated_cost_us"',
            'D_METHOD("get_reserved_estimated_cost_us"',
            "Math::is_finite(p_importance)",
            "p_importance < 0.25 || p_importance > 4.0",
            "3 * lane.estimated_cost_us + p_elapsed_us + 2",
            "lane.overdue_frames < 48",
            "double(MIN(lane.overdue_frames, 120)) * 0.012",
            "reserved_estimated_cost_us + lane.estimated_cost_us > frame_time_budget_us",
            "get_reserved_estimated_cost_us",
        ):
            self.assertIn(item, cpp if item != "get_reserved_estimated_cost_us" else header + cpp)
        self.assertIn("int overdue_frames = 0", header)
        self.assertIn("double importance = 1.0", header)
        self.assertIn("int64_t estimated_cost_us = 0", header)
        self.assertNotIn("SceneTree *", cpp)
        self.assertNotIn("Thread::", cpp)

    def test_game_fallback_and_scene_significance(self):
        script = GDSCRIPT.read_text(encoding="utf-8")
        game = GAME.read_text(encoding="utf-8")
        test = TEST.read_text(encoding="utf-8")
        for method in (
            "set_lane_importance", "get_lane_importance", "get_lane_estimated_cost_us",
            "get_reserved_estimated_cost_us", "suggested_importance",
        ):
            self.assertIn("func " + method, script)
        self.assertIn('native_budget.has_method("set_lane_importance")', game)
        self.assertIn("AmbientTickBudget.suggested_importance(", game)
        self.assertIn("_ambient_budget.set_lane_importance(", game)
        self.assertIn("Albion/AmbientPlannedCPUus", game)
        self.assertIn("old expensive lane is eventually scheduled", test)
        self.assertIn("native/script priority parity", test)

    def test_deterministic_cost_ema(self):
        estimate = 0
        for observed, expected in ((800, 800), (400, 700), (1000, 775), (0, 775)):
            if observed > 0:
                estimate = observed if estimate == 0 else (3 * estimate + observed + 2) // 4
            self.assertEqual(estimate, expected)

    def test_soft_capacity_does_not_block_all_due_channels(self):
        # A channel too costly to fit alone may run periodically; cheap ones
        # are normally preferred. This represents the scheduler's two passes.
        costs = (1500, 100)
        budget = 500
        def preferred(overdue):
            fits = [i for i, c in enumerate(costs) if c <= budget or overdue[i] >= 48]
            if not fits:
                fits = [0, 1]
            priorities = [0.16 * (0.25 if i == 0 else 4.0) + min(overdue[i], 120) * 0.012
                          for i in fits]
            return fits[max(range(len(fits)), key=lambda j: priorities[j])]
        self.assertEqual(preferred([0, 0]), 1)
        self.assertEqual(preferred([60, 0]), 0)


if __name__ == "__main__":
    unittest.main()
