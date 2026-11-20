"""Source-level regression tests for combat-significance animation LOD.

This does not replace compilation of the native gameplay_tags module or a
visual raid benchmark on Apple Metal.
Run: python3 -m unittest tests/modules/test_combat_animation_budget.py -v
"""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
NATIVE_HEADER = ROOT / "modules/gameplay_tags/animation_lod_controller.h"
NATIVE_CPP = ROOT / "modules/gameplay_tags/animation_lod_controller.cpp"
ENGINE_TEST = ROOT / "modules/gameplay_tags/tests/test_gameplay_tags.h"
GAME_POLICY = ROOT / "game/scripts/client/combat_animation_priority.gd"
ENTITY = ROOT / "game/scripts/client/entity_view.gd"
FALLBACK = ROOT / "game/scripts/client/character_anim.gd"
GAME_TEST = ROOT / "game/tests/test_combat_animation_priority.gd"


class CombatAnimationBudgetContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.header = NATIVE_HEADER.read_text(encoding="utf-8")
        cls.cpp = NATIVE_CPP.read_text(encoding="utf-8")
        cls.native_test = ENGINE_TEST.read_text(encoding="utf-8")
        cls.policy = GAME_POLICY.read_text(encoding="utf-8")
        cls.entity = ENTITY.read_text(encoding="utf-8")
        cls.fallback = FALLBACK.read_text(encoding="utf-8")
        cls.game_test = GAME_TEST.read_text(encoding="utf-8")

    def test_native_has_bounded_presentation_only_priority_budget(self):
        self.assertIn("int max_priority_mixers = 8;", self.header)
        self.assertIn("CLAMP(p_count, 0, 32)", self.header)
        self.assertIn("bool high_priority = false;", self.header)
        self.assertIn("set_mixer_high_priority", self.cpp)
        self.assertIn("is_mixer_high_priority", self.cpp)
        self.assertIn("int urgent_slots = max_priority_mixers;", self.cpp)
        self.assertIn(
            "entry.high_priority && base_interval > 1 && urgent_slots > 0",
            self.cpp,
        )
        self.assertIn("urgent_slots--;", self.cpp)
        self.assertIn("const int interval = urgent ? 1 : base_interval;", self.cpp)
        self.assertIn("mixer->advance(entry.accumulated);", self.cpp)

    def test_invisible_and_far_away_actors_stay_culled(self):
        self.assertIn(
            "const int base_interval = update_interval(distance, visible,",
            self.cpp,
        )
        self.assertIn("if (interval == 0) {", self.cpp)
        self.assertIn("continue; // Paused; keep animation state untouched.", self.cpp)
        self.assertIn(
            "const bool want_modifier_cull = modifier_cull_distance > 0.0 &&",
            self.cpp,
        )
        self.assertIn("(!visible || (!urgent && distance > modifier_cull_distance))", self.cpp)

    def test_overlay_is_not_a_second_ik_owner(self):
        self.assertIn("bool manage_modifiers = true;", self.header)
        self.assertIn("entry.manage_modifiers = p_manage_modifiers;", self.cpp)
        self.assertIn("if (entry.manage_modifiers) {", self.cpp)
        self.assertIn('DEFVAL(true)', self.cpp)
        self.assertIn("_anim_lod.register_mixer(upper_layer, false)", self.entity)
        self.assertIn("_anim_lod.unregister_mixer(upper_layer)", self.entity)
        self.assertIn(
            '"set_mixer_high_priority", upper_layer, priority', self.entity
        )
        self.assertIn("lod->register_mixer(overlay, false);", self.native_test)

    def test_authoritative_combat_not_modified(self):
        self.assertIn("static func wants_priority(kind: String, entity: Dictionary)", self.policy)
        self.assertIn("raid_boss", self.policy)
        self.assertIn("elite", self.policy)
        self.assertIn("spitter", self.policy)
        self.assertIn("stagger_seconds", self.policy)
        self.assertNotIn("health =", self.entity)
        self.assertNotIn("client.attack", self.policy)

    def test_stock_godot_promotion_is_visible_and_limited(self):
        self.assertIn("const SLOTS := [0, 1, 4, 8]", self.policy)
        self.assertIn("var preferred: Array[int] = []", self.fallback)
        self.assertIn("model.get_meta(", self.fallback)
        self.assertIn("camera.is_position_in_frustum(", self.fallback)
        self.assertIn("preferred.sort_custom(", self.fallback)
        self.assertIn(
            "mini(CombatAnimationPriority.slots(quality), preferred.size())",
            self.fallback,
        )
        self.assertIn(
            "tiers[preferred[j]] = mini(tiers[preferred[j]], 1)", self.fallback
        )
        self.assertIn('"res://scripts/client/entity_view.gd"', self.game_test)

    def test_quality_changes_and_snapshot_priority_not_polled_per_frame(self):
        self.assertIn("if _priority_quality != quality:", self.entity)
        self.assertIn(
            "if bool(model.get_meta(\"aa_combat_animation_priority\", false)) == priority:",
            self.entity,
        )
        self.assertIn("set_max_priority_mixers", self.entity)
        self.assertIn("_apply_combat_animation_priority(", self.entity)


if __name__ == "__main__":
    unittest.main()
