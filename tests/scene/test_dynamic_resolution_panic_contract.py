"""Validate dynamic resolution panic module wiring and real Albion usage."""
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MODULE = ROOT / "modules" / "dynamic_resolution_panic"
GAME = ROOT / "game" / "scripts" / "client"
TESTS = ROOT / "game" / "tests"


class DynamicResolutionPanicContract(unittest.TestCase):
    def test_native_is_data_only_bounded_and_registered(self):
        code = (MODULE / "dynamic_resolution_panic_policy.cpp").read_text()
        header = (MODULE / "dynamic_resolution_panic_policy.h").read_text()
        registration = (MODULE / "register_types.cpp").read_text()
        self.assertIn("GDREGISTER_CLASS(DynamicResolutionPanicPolicy)", registration)
        self.assertIn("double calculate_scale(", header)
        self.assertIn("p_consecutive_frames < p_required_frames", code)
        self.assertIn("MAX(38.0, p_target_ms * 1.75)", code)
        self.assertIn("p_current_scale - 0.12", code)
        self.assertIn("MAX(p_floor_scale, quantized)", code)
        self.assertNotIn("RenderingServer", code)
        self.assertNotIn("SceneTree", code)
        self.assertNotIn("AudioServer", code)
        methods = ET.parse(MODULE / "doc_classes/DynamicResolutionPanicPolicy.xml")
        self.assertEqual(len(methods.findall("./methods/method")), 1)

    def test_live_game_uses_real_gpu_timing_and_fallback(self):
        controller = (GAME / "graphics_dynamic_resolution.gd").read_text()
        fallback = (GAME / "graphics_resolution_panic.gd").read_text()
        live = (GAME / "online_main.gd").read_text()
        runner = (TESTS / "run_dynamic_resolution_panic.gd").read_text()
        all_tests = (TESTS / "run_all.gd").read_text()
        self.assertIn('EngineFeatures.make("DynamicResolutionPanicPolicy")', controller)
        self.assertIn("PanicPolicy.calculate_scale(", controller)
        self.assertIn("PANIC_FRAMES := 3", controller)
        self.assertIn("_panic_cooldown", controller)
        self.assertIn("static func calculate_scale(", fallback)
        self.assertIn("viewport_get_measured_render_time_gpu", live)
        self.assertIn("_adaptive_resolution.sample_frame(delta, gpu_ms)", live)
        self.assertIn("GraphicsQuality.apply_resolution(get_viewport(), _adaptive_resolution.scale, true)", live)
        self.assertIn("test_graphics_resolution_panic.gd", runner)
        self.assertIn("test_graphics_resolution_panic.gd", all_tests)


if __name__ == "__main__":
    unittest.main()
