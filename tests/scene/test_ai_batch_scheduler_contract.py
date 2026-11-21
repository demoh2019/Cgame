"""Source contracts for stateless native AI batch scheduling and server usage.

These checks validate the integration and a reference SplitMix64 model. They
do not replace native compilation, profiling, or a Godot headless game run.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "modules/behavior_tree"
SERVER = ROOT / "game/scripts/server/game_server.gd"
GAME_TEST = ROOT / "game/tests/test_ai_update_scheduler.gd"

MASK64 = (1 << 64) - 1


def slot_for(agent_id: int, slots: int) -> int:
    x = (agent_id + 0x9e3779b97f4a7c15) & MASK64
    x = ((x ^ (x >> 30)) * 0xbf58476d1ce4e5b9) & MASK64
    x = ((x ^ (x >> 27)) * 0x94d049bb133111eb) & MASK64
    return (x ^ (x >> 31)) % slots


class TestAIBatchSchedulerContract(unittest.TestCase):
    def test_native_api_is_packed_bounded_and_stateless(self):
        header = (BASE / "ai_update_scheduler.h").read_text(encoding="utf-8")
        native = (BASE / "ai_update_scheduler.cpp").read_text(encoding="utf-8")
        self.assertIn("PackedByteArray get_due_mask(", header)
        self.assertIn("const PackedInt64Array &p_agent_ids", header)
        self.assertIn('D_METHOD("get_due_mask", "agent_ids", "tick_index")', native)
        self.assertIn("p_agent_ids.size() > 4096", native)
        self.assertIn("p_tick_index < 0", native)
        self.assertIn("result.resize(p_agent_ids.size())", native)
        self.assertIn("hash_agent_id(p_agent_ids[i])", native)
        self.assertIn("p_tick_index % slots_per_cycle", native)
        self.assertNotIn("Thread::", native)
        self.assertNotIn("SceneTree", native)

    def test_server_applies_index_aligned_mask_with_scalar_fallback(self):
        server = SERVER.read_text(encoding="utf-8")
        self.assertIn("const AI_BATCH_MAX_SIZE := 4096", server)
        self.assertIn("var ai_cohort: Array = zombies.values()", server)
        self.assertIn('has_method("get_due_mask")', server)
        self.assertIn("cohort_ids.resize(ai_cohort.size())", server)
        self.assertIn("cohort_ids[i] = int(ai_cohort[i].id)", server)
        self.assertIn("due_mask = _ai_update_scheduler.get_due_mask(cohort_ids, tick_count)", server)
        self.assertIn("zombie.ai_selection_allowed = due_mask[i] != 0", server)
        self.assertIn("zombie.ai_selection_allowed = _ai_update_scheduler.is_due(zombie.id, tick_count)", server)
        self.assertIn("var result: Dictionary = zombie.think(world, info, delta, rng)", server)
        self.assertIn('"batch_used": batch_used', server)
        self.assertIn('"batch_size": due_mask.size() if batch_used else 0', server)

    def test_game_native_and_legacy_cases_are_registered(self):
        tests = GAME_TEST.read_text(encoding="utf-8")
        runner = (ROOT / "game/tests/run_ai_batch.gd").read_text(encoding="utf-8")
        self.assertIn("Batch phase mask is index-preserving and scalar-equivalent", tests)
        self.assertIn("batch_size", tests)
        self.assertIn("4097", tests)
        self.assertIn('quit(0 if t.failures.is_empty() else 1)', runner)
        self.assertIn("AI BATCH TOTAL:", runner)

    def test_reference_hash_batches_preserve_legacy_decisions(self):
        cohort = list(range(-80, 900)) + [-80, (1 << 63) - 1]
        for slots in (1, 4, 7, 16, 64):
            for tick in range(2 * slots):
                results = [int(slot_for(agent, slots) == tick % slots)
                           for agent in cohort]
                self.assertEqual(results[0], results[-2])
                self.assertEqual(len(results), len(cohort))
                self.assertTrue(all(flag in (0, 1) for flag in results))
            self.assertTrue(all(sum(slot_for(x, slots) == tick
                                    for tick in range(slots)) == 1
                                for x in cohort))


if __name__ == "__main__":
    unittest.main()
