"""Unreal-inspired, cosmetic-only WorldStreamer data layer source contract.

This tests a deterministic transition model and repository integration.
It is NOT a native C++ build, renderer test or CPU speed benchmark.
"""
import unittest
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
NATIVE = ROOT / "scene" / "main"
GAME = ROOT / "game" / "scripts" / "client"


def simulate_layer(active, within_radius, enabled):
    return bool(enabled and (active or within_radius))


class TestWorldStreamerCosmeticLayers(unittest.TestCase):
    def test_engine_interface_and_bounded_decisions(self):
        header = (NATIVE / "world_streamer.h").read_text()
        impl = (NATIVE / "world_streamer.cpp").read_text()
        docs = ET.parse(ROOT / "doc" / "classes" / "WorldStreamer.xml").getroot()
        self.assertIn("MAX_SIMULATION_LAYERS = 16", header)
        self.assertIn("bool set_simulation_layer_enabled(", header)
        self.assertIn("get_cell_simulation_layer(", header)
        self.assertIn("p_chunk->has_method(SNAME(\"get_streaming_simulation_layer\"))", impl)
        self.assertIn("disabled_simulation_layer_count == 0", impl)
        self.assertIn("const bool desired = _simulation_layer_allows(entry.key)", impl)
        self.assertIn("const bool simulation_active = radius_allows && layer_allows;", impl)
        self.assertIn("cell_simulation_layers.erase(p_cell);", impl)
        self.assertIn("cell_simulation_layers.clear();", impl)
        self.assertIn('D_METHOD("set_simulation_layer_enabled", "layer", "enabled")', impl)
        names = {m.get("name") for m in docs.findall("methods/method")}
        self.assertTrue({"set_simulation_layer_enabled", "is_simulation_layer_enabled",
                         "get_cell_simulation_layer", "get_simulation_layer_count"} <= names)
        self.assertNotIn("queue_free()", impl[impl.index("bool WorldStreamer::set_simulation_layer_enabled("):
                                                impl.index("void WorldStreamer::_set_chunk_simulation_active(")])

    def test_authoritative_world_never_toggled(self):
        policy = (GAME / "world_streaming_policy.gd").read_text()
        game = (GAME / "online_main.gd").read_text()
        view = (GAME / "chunk_view.gd").read_text()
        self.assertIn('return &"SurfaceCosmetics"', view)
        self.assertIn("func apply_simulation_layers(", policy)
        self.assertIn("streamer.call(\"set_simulation_layer_enabled\"", policy)
        self.assertIn("WorldStreamingPolicy.apply_simulation_layers(streamer,", game)
        self.assertIn("Dungeon.is_underground(position.x)", game)
        self.assertIn("set_streaming_simulation_active(active: bool)", view)
        self.assertNotIn("queue_free()", policy)
        self.assertNotIn("get_streaming_simulation_layer", (ROOT / "game" / "scripts" /
                         "shared" / "world_gen.gd").read_text())

    def test_transition_model(self):
        # Layer gates only cosmetic processing and has no effect on residency.
        for active in (False, True):
            for near in (False, True):
                self.assertFalse(simulate_layer(active, near, False))
                self.assertEqual(simulate_layer(active, near, True), active or near)
        test = (ROOT / "game/tests/test_world_streamer_simulation_tiers.gd").read_text()
        self.assertIn("surface and dungeon simulation chunks", test)
        self.assertIn("suspension never unloads play-critical chunks", test)
        self.assertIn("resuming simulated visuals never replaces", test)


if __name__ == "__main__":
    unittest.main()
