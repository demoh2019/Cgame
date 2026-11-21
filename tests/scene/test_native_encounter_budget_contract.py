"""Fast static and independent numeric contracts for native encounter pressure.

Only a Cgame native build and headless game tests can confirm binary parity.
"""
import math
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
MODULE = ROOT / "modules" / "behavior_tree"
GAME = ROOT / "game" / "scripts" / "shared" / "world_encounter_director.gd"
SERVER = ROOT / "game" / "scripts" / "server" / "game_server.gd"


def spawn_budget(total, nearby, health, zone, global_limit=150, soft=8, dense=12,
                 hard=20, base=7, max_squad=10, zone_bonus_cap=3):
    if total < 0 or nearby < 0 or not math.isfinite(health):
        return 0
    headroom = global_limit - total
    if headroom <= 0 or nearby >= hard:
        return 0
    budget = min(max_squad, base + min(max(zone, 0), zone_bonus_cap))
    if nearby >= dense:
        budget = min(budget, 2)
    elif nearby >= soft:
        budget = min(budget, 4)
    hp = min(max(health, 0.0), 1.0)
    if hp <= 0.30:
        budget = min(budget, 2)
    elif hp <= 0.55:
        budget = min(budget, 4)
    return min(max(budget, 0), headroom)


def respite(base, nearby, health, soft=8, dense=12):
    if not math.isfinite(base) or base < 0 or not math.isfinite(health):
        return 0.0
    bonus = 45.0 if nearby >= dense else 20.0 if nearby >= soft else 0.0
    bonus += 30.0 if health <= .30 else 15.0 if health <= .55 else 0.0
    return min(max(base + bonus, base), base + 75.0)


class NativeEncounterBudgetContract(unittest.TestCase):
    def test_engine_class_registration_and_docs(self):
        reg = (MODULE / "register_types.cpp").read_text()
        config = (MODULE / "config.py").read_text()
        header = (MODULE / "ai_encounter_budget.h").read_text()
        code = (MODULE / "ai_encounter_budget.cpp").read_text()
        test = (MODULE / "tests" / "test_ai_encounter_budget.h").read_text()
        self.assertIn("GDREGISTER_CLASS(AIEncounterBudget);", reg)
        self.assertIn('"AIEncounterBudget"', config)
        for symbol in ("configure_limits", "get_spawn_budget",
                       "get_respite_seconds", "get_local_hard_limit"):
            self.assertIn(symbol, header)
            self.assertIn(symbol, code)
        self.assertIn("!Math::is_finite(p_health_ratio)", code)
        self.assertIn("return CLAMP(budget, 0, headroom)", code)
        self.assertIn("[AIEncounterBudget]", test)
        self.assertNotIn("SceneTree::", code)
        self.assertNotIn("RandomNumberGenerator", code)
        parsed = ET.parse(MODULE / "doc_classes" / "AIEncounterBudget.xml")
        self.assertEqual(parsed.getroot().attrib["name"], "AIEncounterBudget")

    def test_real_authoritative_game_uses_optional_engine_policy(self):
        game = GAME.read_text()
        server = SERVER.read_text()
        tests = (ROOT / "game" / "tests" / "test_world_encounter_director.gd").read_text()
        runner = (ROOT / "game" / "tests" / "run_native_encounter_budget.gd").read_text()
        self.assertIn('ClassDB.class_exists("AIEncounterBudget")', game)
        self.assertIn('_native_budget.call("get_spawn_budget"', game)
        self.assertIn('_native_budget.call("get_respite_seconds"', game)
        self.assertIn("prefer_native: bool = true", game)
        self.assertIn("WorldEncounterDirector.spawn_budget(", server)
        self.assertIn("WorldEncounterDirector.respite_seconds(", server)
        self.assertIn('t.current = "native encounter pacing and stock Godot parity"', tests)
        self.assertIn("ENCOUNTER BUDGET TOTAL:", runner)

    def test_numeric_limits_and_reference_truth_table(self):
        self.assertEqual(spawn_budget(0, 0, 1., 0), 7)
        self.assertEqual(spawn_budget(0, 0, 1., 3), 10)
        self.assertEqual(spawn_budget(0, 8, 1., 3), 4)
        self.assertEqual(spawn_budget(0, 12, 1., 3), 2)
        self.assertEqual(spawn_budget(0, 20, 1., 3), 0)
        self.assertEqual(spawn_budget(0, 0, .2, 3), 2)
        self.assertEqual(spawn_budget(149, 0, 1., 3), 1)
        self.assertEqual(spawn_budget(0, 0, math.nan, 3), 0)
        for total in [-1, 0, 1, 149, 150, 151]:
            for nearby in [-1, 0, 7, 8, 11, 12, 19, 20]:
                for health in [-1.0, .3, .55, 1., 2.]:
                    for zone in [-3, 0, 1, 3, 20]:
                        result = spawn_budget(total, nearby, health, zone)
                        self.assertGreaterEqual(result, 0)
                        self.assertLessEqual(result, max(0, 150 - total))
                        if total >= 150 or nearby >= 20:
                            self.assertEqual(result, 0)
        self.assertEqual(respite(100., 0, 1.), 100.)
        self.assertEqual(respite(100., 8, 1.), 120.)
        self.assertEqual(respite(100., 12, .2), 175.)
        for nearby in range(0, 21):
            for health in (.2, .5, 1.):
                delay = respite(90., nearby, health)
                self.assertGreaterEqual(delay, 90.)
                self.assertLessEqual(delay, 165.)
        self.assertEqual(spawn_budget(0, 0, 1., 4, 300, 4, 6, 12, 3, 7, 4), 7)
        self.assertEqual(spawn_budget(0, 6, 1., 4, 300, 4, 6, 12, 3, 7, 4), 2)


if __name__ == "__main__":
    unittest.main()
