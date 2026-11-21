"""Native audio probe scheduler source contracts (not a native CI substitute)."""
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FX = ROOT / "modules/gameplay_fx"
GAME = ROOT / "game/scripts/client"
TEST = ROOT / "game/tests"


class AudioOcclusionProbeContract(unittest.TestCase):
    def test_engine_registration_and_bounded_pure_policy(self):
        registration = (FX / "register_types.cpp").read_text()
        header = (FX / "audio_occlusion_probe_planner.h").read_text()
        cpp = (FX / "audio_occlusion_probe_planner.cpp").read_text()
        self.assertIn("GDREGISTER_CLASS(AudioOcclusionProbePlanner);", registration)
        self.assertIn("MAX_VOICES = 128", cpp)
        self.assertIn("MAX_PROBES = 16", cpp)
        self.assertIn("p_now_seconds - p_next_due_seconds[i]", cpp)
        self.assertIn("ids.has(p_ids[i])", cpp)
        self.assertIn("p_next_due_seconds[i] > p_now_seconds", cpp)
        self.assertIn("PackedInt32Array select_due", header)
        self.assertNotIn("SceneTree", cpp)
        self.assertNotIn("intersect_ray", cpp)
        self.assertNotIn("AudioServer", cpp)
        methods = ET.parse(FX / "doc_classes/AudioOcclusionProbePlanner.xml").findall("./methods/method")
        self.assertIn("select_due", [m.get("name") for m in methods])

    def test_game_integration_and_fallback(self):
        live = (GAME / "audio.gd").read_text()
        portable = (GAME / "audio_occlusion_probes.gd").read_text()
        tests = (TEST / "test_audio_occlusion_probe_planner.gd").read_text()
        runner = (TEST / "run_audio.gd").read_text()
        full = (TEST / "run_all.gd").read_text()
        self.assertIn('EngineFeatures.make("AudioOcclusionProbePlanner")', live)
        self.assertIn("AudioOcclusionProbes.select_due", live)
        self.assertIn("probe_slots.has(index)", live)
        self.assertIn("OBSTRUCTION_RAYS_PER_TICK := 3", live)
        self.assertIn('state.intersect_ray(ray)', live)
        self.assertIn('record["terrain_blocked"] = terrain_blocked', live)
        self.assertIn("func select_due(", portable)
        self.assertIn("MAX_PROBES := 16", portable)
        self.assertIn("native/script fair scheduling parity", tests)
        self.assertIn("test_audio_occlusion_probe_planner.gd", runner)
        self.assertIn("test_audio_occlusion_probe_planner.gd", full)


if __name__ == "__main__":
    unittest.main()
