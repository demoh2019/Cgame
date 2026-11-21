"""Source contract checks for the optional native FrameUpdateBudget module.

These tests are not a substitute for compiling the custom Godot engine or for
running tests/scene on a native editor build.
"""
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
NATIVE = ROOT / "modules/frame_update_budget"
GAME = ROOT / "game/scripts/client"
TESTS = ROOT / "game/tests"


class TestFrameBudgetContract(unittest.TestCase):
    def test_registration_and_documentation(self):
        config = (NATIVE / "config.py").read_text()
        registration = (NATIVE / "register_types.cpp").read_text()
        self.assertIn('return ["FrameUpdateBudget"]', config)
        self.assertIn("GDREGISTER_CLASS(FrameUpdateBudget);", registration)
        cls = ET.parse(NATIVE / "doc_classes/FrameUpdateBudget.xml").getroot()
        self.assertEqual(cls.get("name"), "FrameUpdateBudget")
        names = {method.get("name") for method in cls.findall("./methods/method")}
        for name in (
            "register_lane", "unregister_lane", "get_lane_count", "configure",
            "begin_frame", "consume", "reset", "updated_total", "skipped_total",
            "current_budget", "pressure_percent", "last_frame_counts",
        ):
            self.assertIn(name, names)

    def test_native_has_bounded_inputs_and_atomic_configuration(self):
        src = (NATIVE / "frame_update_budget.cpp").read_text()
        header = (NATIVE / "frame_update_budget.h").read_text()
        self.assertIn("lanes.size() >= 64", src)
        self.assertIn("Math::is_finite(p_delta)", src)
        self.assertIn("Math::is_finite(p_rates[i])", src)
        self.assertIn("MIN(lane.elapsed + p_delta, max_step)", src)
        self.assertIn("profile_dirty || next_quality != quality", src)
        self.assertIn("spent >= budget", src)
        self.assertIn("p_force || quality_changed", src)
        self.assertIn("for (int i = 0; i < 4; i++)", src)
        self.assertIn("Vector<Lane>", header)
        self.assertIn("Vector<int> reserved_lanes", header)
        self.assertIn("tie_start", src)
        self.assertIn("reserved_lanes.has(index)", src)
        self.assertIn("reserved_lanes.remove_at", src)
        self.assertNotIn("SceneTree", src)
        self.assertNotIn("Thread::", src)

    def test_game_uses_native_with_safe_fallback(self):
        main = (GAME / "online_main.gd").read_text()
        fallback = (GAME / "ambient_tick_budget.gd").read_text()
        tests = (TESTS / "test_ambient_tick_budget.gd").read_text()
        runner = (TESTS / "run_all.gd").read_text()
        self.assertIn('EngineFeatures.has("FrameUpdateBudget")', main)
        self.assertIn('EngineFeatures.make("FrameUpdateBudget")', main)
        self.assertIn("AmbientTickBudget.new()", main)
        self.assertIn('ClassDB.class_exists("FrameUpdateBudget")', tests)
        self.assertIn("test_ambient_tick_budget.gd", runner)
        self.assertIn("_reserved", fallback)
        self.assertIn("_tie_start", fallback)
        self.assertIn("_reserved.erase(lane)", fallback)
        self.assertIn("fair ambient slots across fixed-order cosmetic systems", tests)
        for lane in ('dragonflies', 'dust_devils', 'tumbleweeds', 'dusk_bats'):
            self.assertIn('_ambient_budget.consume("%s"' % lane, main)
            self.assertIn('"%s"' % lane, fallback)
        self.assertIn("Performance.add_custom_monitor", main)
        self.assertIn("Performance.remove_custom_monitor", main)


if __name__ == "__main__":
    unittest.main()
