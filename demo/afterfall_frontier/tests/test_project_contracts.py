"""Repository contracts for the original survival sandbox vertical slice.

The headless Godot smoke test exercises actual runtime behavior; these
stdlib checks are fast, portable guardrails against incomplete packaging
and accidental regression of major mechanics.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
GAME = ROOT / "demo" / "afterfall_frontier"


class AfterfallFrontierContracts(unittest.TestCase):
    def test_self_contained_editor_project_files(self):
        expected = [
            "project.godot", "main.tscn", "world.gd", "rules.gd",
            "survivor.gd", "smoke_test.gd", "README.md",
        ]
        for filename in expected:
            with self.subTest(filename=filename):
                self.assertTrue((GAME / filename).is_file())
                self.assertGreater((GAME / filename).stat().st_size, 40)
        self.assertIn('run/main_scene="res://main.tscn"',
                      (GAME / "project.godot").read_text())
        self.assertIn('path="res://world.gd"', (GAME / "main.tscn").read_text())

    def test_original_survival_loop_connected(self):
        world = (GAME / "world.gd").read_text()
        state = (GAME / "survivor.gd").read_text()
        rules = (GAME / "rules.gd").read_text()
        for token in (
            "func _gather_or_recover()", "func _attack()", "func _update_infected(",
            "func _handle_death()", "func _save_profile()", "func _load_profile()",
            "func _store_stash()", "func _withdraw_stash()",
            "func _draw()", "func _refresh_hud()", "survivor.gather(",
            "survivor.craft(", "survivor.build_shelter(",
        ):
            with self.subTest(token=token):
                self.assertIn(token, world)
        for token in (
            "func gather(", "func craft(", "func build_shelter(",
            "func store(", "func withdraw(", "func sell(", "func buy(",
            "func damage(", "func respawn(", "func tick(",
            "func snapshot(", "func import_snapshot(",
        ):
            self.assertIn(token, state)
        for recipe in ("axe", "pickaxe", "spear", "bandage", "armor"):
            self.assertIn(f'"{recipe}":', rules)
        self.assertIn("can_gather", rules)
        self.assertIn("MAX_CARRY_WEIGHT", rules)
        self.assertIn("sanitize_bag", rules)

    def test_zones_and_nonfake_multiplayer_claims(self):
        rules = (GAME / "rules.gd").read_text()
        readme = (GAME / "README.md").read_text()
        self.assertEqual(rules.count('"full_loot":'), 3)
        self.assertIn('"full_loot": true', rules)
        self.assertIn('"pvp": false', rules)
        self.assertIn('"pvp": true', rules)
        self.assertIn("real player market", readme)
        self.assertIn("no network PvP", readme)
        self.assertIn("dedicated server", readme)
        self.assertIn("original", readme.lower())

    def test_input_to_action_mapping_and_scene_smoke(self):
        world = (GAME / "world.gd").read_text()
        smoke = (GAME / "smoke_test.gd").read_text()
        for key in ("KEY_E", "KEY_F", "KEY_TAB", "KEY_C", "KEY_B",
                    "KEY_T", "KEY_Y", "KEY_K", "KEY_L",
                    "KEY_R", "KEY_H", "KEY_J", "KEY_F5", "KEY_F9"):
            self.assertRegex(world, rf"(?m)^\s*{key}:")
        self.assertIn("await physics_frame", smoke)
        self.assertIn("res://main.tscn", smoke)
        self.assertIn("_test_crafting_and_shelter()", smoke)
        self.assertIn("_test_survival_economy_and_death()", smoke)
        self.assertIn("_test_save_roundtrip()", smoke)
        self.assertIn("PASS: Afterfall Frontier", smoke)

    def test_gameplay_scripts_have_no_remote_dependencies_or_copied_assets(self):
        scripts = [
            (GAME / name).read_text()
            for name in ("world.gd", "rules.gd", "survivor.gd", "smoke_test.gd")
        ]
        for name, script in zip(("world", "rules", "survivor", "smoke"), scripts):
            with self.subTest(script=name):
                self.assertTrue(script.startswith("extends "))
                self.assertNotIn("HTTPRequest.new()", script)
                self.assertNotIn("OS.execute(", script)
                self.assertNotIn("load(\"https://", script)
        self.assertIn("draw_circle(", scripts[0])
        self.assertIn("draw_rect(", scripts[0])
        self.assertIn("Camera2D.new()", scripts[0])


if __name__ == "__main__":
    unittest.main()
