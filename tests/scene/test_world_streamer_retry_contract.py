"""Source checks for the native WorldStreamer bounded-retry contract.

Run: python3 -m unittest tests/scene/test_world_streamer_retry_contract.py -v
Runtime behavior is covered separately by game/tests/test_world_streamer_retry.gd.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
CPP = (ROOT / "scene/main/world_streamer.cpp").read_text(encoding="utf-8")
HEADER = (ROOT / "scene/main/world_streamer.h").read_text(encoding="utf-8")
GAME = (ROOT / "game/scripts/client/online_main.gd").read_text(encoding="utf-8")
HUD = (ROOT / "game/scripts/client/ui_accessibility_layer.gd").read_text(encoding="utf-8")


class WorldStreamerRetryContract(unittest.TestCase):
    def test_default_off_and_attempts_bounded(self):
        self.assertIn("int max_auto_retries = 0;", HEADER)
        self.assertIn("CLAMP(p_count, 0, 8)", CPP)
        self.assertIn("state.attempts < max_auto_retries", CPP)
        self.assertIn("state.next_retry_usec = 0;", CPP)

    def test_every_real_failure_uses_one_retry_policy(self):
        self.assertEqual(CPP.count("failed.insert("), 1)
        self.assertEqual(CPP.count('SNAME("chunk_load_failed")'), 1)
        self.assertIn("_record_failure(cell, path);", CPP)
        self.assertIn("_record_failure(cell, String(\"generator call failed\"));", CPP)
        self.assertIn("_record_failure(cell, String(\"generator returned a non-Node value\"));", CPP)
        self.assertIn("missing.insert(cell); // Null is an intentionally empty cell", CPP)

    def test_retry_state_released_on_success_reset_and_unload(self):
        self.assertIn("retry_states.erase(p_cell);", CPP)
        self.assertIn("retry_states.clear();", CPP)
        self.assertIn("retry_states.erase(cell);", CPP)
        self.assertIn("WorldStreamingGrid::distance_to_cell(p_focus", CPP)

    def test_retries_do_not_bypass_existing_frame_budget(self):
        self.assertIn("_update_retries(position, keep_radius);", CPP)
        self.assertIn("_run_generator_queue(frame_budget, frame_started_usec);", CPP)
        self.assertIn("r_instantiation_budget--;", CPP)
        self.assertNotIn("chunk_generator.callp", CPP.split("void WorldStreamer::_update_retries", 1)[1].split("int WorldStreamer::get_retry_pending_count", 1)[0])

    def test_game_actually_uses_engine_recovery(self):
        self.assertIn("streamer.max_auto_retries = 2", GAME)
        self.assertIn("streamer.retry_initial_delay = 0.5", GAME)
        self.assertIn("get_retry_pending_count()", HUD)


if __name__ == "__main__":
    unittest.main()
