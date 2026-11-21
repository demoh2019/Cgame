"""Source and deterministic numerical contracts for native crowd pose planning.

These are quick validation checks, not a native engine build or FPS test.
"""
import math
import random
import unittest
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
MODULE = ROOT / "modules/crowd_animation_tier_planner"
CPP = MODULE / "crowd_animation_tier_planner.cpp"
GAME = ROOT / "game/scripts/client/character_anim.gd"
GAME_TEST = ROOT / "game/tests/test_crowd_animation_tier_planner.gd"
RUNNER = ROOT / "game/tests/run_all.gd"


def plan(distances, priority, full_budget, priority_budget):
    if len(distances) != len(priority) or len(distances) > 16384:
        return []
    if not 0 <= full_budget <= 256 or not 0 <= priority_budget <= 256:
        return []
    if any(not math.isfinite(d) or d < 0 for d in distances):
        return []
    tiers = [0 if d < 22 else 1 if d < 38 else 2 if d < 60 else
             3 if d < 90 else 4 for d in distances]
    eligible_full = sorted((i for i, d in enumerate(distances) if d < 22),
                           key=lambda i: (distances[i], i))
    for i in eligible_full:
        tiers[i] = 1
    for i in eligible_full[:full_budget]:
        tiers[i] = 0
    eligible_combat = sorted(
        (i for i, d in enumerate(distances) if priority[i] and d < 90),
        key=lambda i: (distances[i], i))
    for i in eligible_combat[:priority_budget]:
        tiers[i] = min(tiers[i], 1)
    return tiers


class TestCrowdPlanner(unittest.TestCase):
    def test_native_source_api(self):
        header = (MODULE / "crowd_animation_tier_planner.h").read_text()
        cpp = CPP.read_text()
        register = (MODULE / "register_types.cpp").read_text()
        xml = ET.parse(MODULE / "doc_classes/CrowdAnimationTierPlanner.xml").getroot()
        self.assertIn("PackedInt32Array plan_tiers(", header)
        self.assertIn('D_METHOD("plan_tiers"', cpp)
        self.assertIn("GDREGISTER_CLASS(CrowdAnimationTierPlanner)", register)
        self.assertEqual(xml.get("name"), "CrowdAnimationTierPlanner")
        for contract in (
            "count > 16384", "p_full_budget > 256", "p_priority_budget > 256",
            "Math::is_finite(p_distances[i])", "insert_top(nearest_full",
            "insert_top(nearest_critical", "p_priority_flags[i] != 0",
            "p_distances[i] < 0.0", "p_priority_flags.size()",
        ):
            self.assertIn(contract, cpp)
        self.assertNotIn("SceneTree::", cpp)
        self.assertNotIn("AnimationPlayer", cpp)

    def test_game_direct_integration_and_fallback(self):
        game = GAME.read_text()
        tests = GAME_TEST.read_text()
        runner = RUNNER.read_text()
        self.assertIn("static func plan_crowd_tiers(", game)
        self.assertIn('ClassDB.class_exists("CrowdAnimationTierPlanner")', game)
        self.assertIn('ClassDB.instantiate("CrowdAnimationTierPlanner")', game)
        self.assertIn("priority_mask.append(1 if critical else 0)", game)
        self.assertIn("plan_crowd_tiers_stable(distances, priority_mask,", game)
        self.assertIn("previous_tiers.append(int(model.get(\"_lod_tier\")))", game)
        self.assertIn("plan_tiers_stable", cpp)
        self.assertIn("model.set_anim_lod(tiers[i])", game)
        self.assertIn("model.set_look_point(", game)
        self.assertIn("test_crowd_animation_tier_planner.gd", runner)
        self.assertIn("native/script parity", tests)

    def test_distance_boundaries_and_combat(self):
        d = [2, 4, 30, 55, 80, 100]
        flags = [0, 0, 0, 1, 1, 1]
        self.assertEqual(plan(d, flags, 1, 1), [0, 1, 1, 1, 3, 4])
        self.assertEqual(plan(d, flags, 1, 2), [0, 1, 1, 1, 1, 4])
        self.assertEqual(plan([5, 5, 5, 22, 38, 60, 90], [1]*7, 1, 0),
                         [0, 1, 1, 1, 2, 3, 4])

    def test_tie_stability_and_caps(self):
        for count in (0, 1, 3, 16, 128, 1024):
            rng = random.Random(4985 + count)
            d = [rng.randrange(0, 125) for _ in range(count)]
            flags = [rng.randrange(0, 2) for _ in range(count)]
            for full in (0, 1, 4, 14):
                for combat in (0, 1, 4, 8):
                    result = plan(d, flags, full, combat)
                    self.assertEqual(len(result), count)
                    self.assertLessEqual(sum(x == 0 for x in result), full)
                    # Once a character exceeds the far boundary, combat never
                    # grants extra priority, even when flags are set.
                    for i, value in enumerate(result):
                        if d[i] >= 90:
                            self.assertEqual(value, 4)

    def test_reject_corrupt_inputs(self):
        self.assertEqual(plan([1, 2], [1], 1, 1), [])
        self.assertEqual(plan([float("nan")], [1], 1, 1), [])
        self.assertEqual(plan([-1], [0], 1, 1), [])
        self.assertEqual(plan([5], [0], 257, 0), [])
        self.assertEqual(plan([5], [0], 0, -1), [])
        self.assertEqual(plan([1.0]*16385, [1]*16385, 1, 1), [])


if __name__ == "__main__":
    unittest.main()
