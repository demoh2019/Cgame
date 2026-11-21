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


def plan(distances, priority, full_budget, priority_budget, visible=None):
    if len(distances) != len(priority) or len(distances) > 16384:
        return []
    if visible is not None and len(distances) != len(visible):
        return []
    if not 0 <= full_budget <= 256 or not 0 <= priority_budget <= 256:
        return []
    if any(not math.isfinite(d) or d < 0 for d in distances):
        return []
    tiers = [0 if d < 22 else 1 if d < 38 else 2 if d < 60 else
             3 if d < 90 else 4 for d in distances]
    if visible is not None:
        tiers = [max(tier, 2) if not visible[i] else tier
                 for i, tier in enumerate(tiers)]
    eligible_full = sorted(
        (i for i, d in enumerate(distances)
         if d < 22 and (visible is None or visible[i])),
        key=lambda i: (distances[i], i))
    for i in eligible_full:
        tiers[i] = 1
    for i in eligible_full[:full_budget]:
        tiers[i] = 0
    eligible_combat = sorted(
        (i for i, d in enumerate(distances)
         if priority[i] and d < 90 and (visible is None or visible[i])),
        key=lambda i: (distances[i], i))
    for i in eligible_combat[:priority_budget]:
        tiers[i] = min(tiers[i], 1)
    return tiers



def plan_stable(distances, priority, visible, retained, full_budget,
                priority_budget, hysteresis=1.5):
    """Independent Python oracle for the stateless retained-IK top-K."""
    if (len(distances) != len(retained) or
            len(distances) != len(visible) or
            not math.isfinite(hysteresis) or not 0 <= hysteresis <= 8):
        return []
    if not 0 <= full_budget <= 256:
        return []
    tiers = plan(distances, priority, 0, priority_budget, visible)
    if len(tiers) != len(distances):
        return []
    candidates = sorted(
        (i for i, d in enumerate(distances) if d < 22 and visible[i]),
        key=lambda i: (max(0, distances[i] -
                           (hysteresis if retained[i] else 0)), i))
    for i in candidates[:full_budget]:
        tiers[i] = 0
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
        self.assertIn("plan_crowd_tiers_costed(distances, priority_mask,", game)
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

    def test_visibility_reclaims_full_rate_slots(self):
        d = [2, 4, 6, 55, 80, 100]
        priority = [1, 0, 0, 1, 1, 1]
        visible = [0, 1, 1, 1, 0, 1]
        self.assertEqual(plan(d, priority, 1, 1, visible), [2, 0, 1, 1, 3, 4])
        self.assertEqual(plan(d, priority, 16, 16, [0] * 6),
                         [2, 2, 2, 2, 3, 4])
        self.assertEqual(plan(d, priority, 1, 1, [1] * 6),
                         plan(d, priority, 1, 1))
        self.assertEqual(plan(d, priority, 1, 1, [1]), [])
        self.assertEqual(plan([5, 5, 5], [0, 0, 0], 1, 0, [0, 1, 1]),
                         [2, 0, 1])
        for seed in range(10):
            rng = random.Random(9000 + seed)
            dist = [rng.randrange(0, 120) for _ in range(240)]
            priority = [rng.randrange(0, 2) for _ in dist]
            visible = [rng.randrange(0, 2) for _ in dist]
            tiers = plan(dist, priority, 8, 4, visible)
            self.assertEqual(len(tiers), len(dist))
            self.assertLessEqual(tiers.count(0), 8)
            for i, tier in enumerate(tiers):
                if visible[i] == 0:
                    self.assertGreaterEqual(tier, 2)
                if dist[i] >= 90:
                    self.assertEqual(tier, 4)

    def test_visible_native_game_contracts(self):
        header = (MODULE / "crowd_animation_tier_planner.h").read_text()
        cpp = CPP.read_text()
        game = GAME.read_text()
        self.assertIn("PackedInt32Array plan_visible_tiers(", header)
        self.assertIn('D_METHOD("plan_visible_tiers"', cpp)
        self.assertIn("p_visible_flags->size() != count", cpp)
        self.assertIn("tiers[i] = visible ?", cpp)
        self.assertIn('has_method("plan_visible_tiers")', game)
        self.assertIn("visible_mask.append(1 if visible else 0)", game)
        self.assertIn("model.is_visible_in_tree()", game)
        self.assertIn("model.set_anim_lod(tiers[i])", game)

    def test_stable_ik_retains_previous_visible_owner(self):
        d = [10, 10.4, 21, 22, 50]
        p = [0, 0, 0, 1, 1]
        v = [1, 1, 1, 1, 1]
        held = [0, 1, 1, 1, 0]
        self.assertEqual(plan_stable(d, p, v, held, 1, 1),
                         [1, 0, 1, 1, 2])
        self.assertEqual(plan_stable(d, p, [1, 0, 1, 1, 1],
                                     held, 1, 1),
                         [0, 2, 1, 1, 2])
        self.assertEqual(plan_stable([8, 10.4, 21, 22, 50],
                                     p, v, held, 1, 1),
                         [0, 1, 1, 1, 2])
        self.assertEqual(plan_stable(d, p, v, held, 1, 1, 0),
                         plan(d, p, 1, 1, v))
        self.assertEqual(plan_stable(d, p, v, [0] * 5, 1, 1),
                         plan(d, p, 1, 1, v))
        self.assertEqual(plan_stable(d, p, v, [1], 1, 1), [])
        self.assertEqual(plan_stable(d, p, v, held, 1, 1, -1), [])
        self.assertEqual(plan_stable(d, p, v, held, 1, 1, math.nan), [])
        self.assertEqual(plan_stable(d, p, v, held, 1, 1, 8.1), [])
        self.assertEqual(plan_stable([10, 11.5, 22], [0]*3,
                                     [1]*3, [0, 1, 1], 1, 0),
                         [0, 1, 1])  # Stable index ties at effective 10m.

    def test_stable_ik_random_caps_and_visibility(self):
        for seed in range(12):
            rng = random.Random(14150 + seed)
            d = [rng.randrange(0, 1100) / 10 for _ in range(128)]
            p = [rng.randrange(0, 2) for _ in d]
            v = [rng.randrange(0, 2) for _ in d]
            held = [rng.randrange(0, 2) for _ in d]
            for cap in (0, 1, 4, 14):
                for h in (0.0, 1.5, 8.0):
                    tiers = plan_stable(d, p, v, held, cap, 8, h)
                    self.assertEqual(len(tiers), len(d))
                    self.assertLessEqual(tiers.count(0), cap)
                    for i, tier in enumerate(tiers):
                        if not v[i]:
                            self.assertGreaterEqual(tier, 2)
                        if d[i] >= 22:
                            self.assertNotEqual(tier, 0)
                        if d[i] >= 90:
                            self.assertEqual(tier, 4)

    def test_stable_ik_native_and_runtime_integration(self):
        header = (MODULE / "crowd_animation_tier_planner.h").read_text()
        cpp = CPP.read_text()
        game = GAME.read_text()
        model = (ROOT / "game/scripts/client/character_model.gd").read_text()
        xml = ET.parse(MODULE / "doc_classes/CrowdAnimationTierPlanner.xml")
        self.assertIn("PackedInt32Array plan_visible_tiers_stable(", header)
        self.assertIn('D_METHOD("plan_visible_tiers_stable"', cpp)
        self.assertIn("p_retained_full_flags->size() != count", cpp)
        self.assertIn("distance - (retained ? p_hysteresis : 0.0)", cpp)
        self.assertIn("tier == 0", cpp)
        self.assertIn('has_method("plan_visible_tiers_stable")', game)
        self.assertIn('retained_full_mask.append(', game)
        self.assertIn('model.set_meta("aa_full_ik_retained", full_ik_now)', game)
        self.assertIn('set_meta("aa_full_ik_retained", false)', model)
        self.assertIn('name="plan_visible_tiers_stable"', ET.tostring(
            xml.getroot(), encoding="unicode"))

    def test_reject_corrupt_inputs(self):
        self.assertEqual(plan([1, 2], [1], 1, 1), [])
        self.assertEqual(plan([float("nan")], [1], 1, 1), [])
        self.assertEqual(plan([-1], [0], 1, 1), [])
        self.assertEqual(plan([5], [0], 257, 0), [])
        self.assertEqual(plan([5], [0], 0, -1), [])
        self.assertEqual(plan([1.0]*16385, [1]*16385, 1, 1), [])


if __name__ == "__main__":
    unittest.main()
