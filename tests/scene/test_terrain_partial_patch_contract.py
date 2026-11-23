"""Source guard for P1 atomic native landscape edits and Albion streamed terrain.

This does not replace a real native engine build, physics checks or GPU tests.
"""
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]


class TestTerrainPartialPatchContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.h = (ROOT / "scene/3d/chunked_terrain_3d.h").read_text()
        cls.cpp = (ROOT / "scene/3d/chunked_terrain_3d.cpp").read_text()
        cls.game = (ROOT / "game/scripts/client/terrain_live_patch.gd").read_text()
        cls.online = (ROOT / "game/scripts/client/online_main.gd").read_text()
        cls.chunk = (ROOT / "game/scripts/client/chunk_view.gd").read_text()
        cls.native_tests = (ROOT / "tests/scene/test_chunked_terrain_3d.cpp").read_text()
        cls.game_tests = (ROOT / "game/tests/test_terrain_live_patch.gd").read_text()

    def test_engine_api_registered_and_bounded(self):
        self.assertIn("bool apply_height_patch(", self.h)
        self.assertIn("real_t get_chunk_lod_error(", self.h)
        for marker in (
            'D_METHOD("apply_height_patch", "region", "heights")',
            'D_METHOD("get_chunk_lod_error", "chunk", "lod")',
            "bool ChunkedTerrain3D::apply_height_patch(",
            "real_t ChunkedTerrain3D::get_chunk_lod_error(",
        ):
            self.assertIn(marker, self.cpp)
        fn = self.cpp.split("bool ChunkedTerrain3D::apply_height_patch(", 1)[1].split(
            "void ChunkedTerrain3D::update_region(", 1
        )[0]
        for marker in (
            "!data_from_script",
            "p_region.position.x < 0",
            "p_region.position.y < 0",
            "p_region.position.x > data_width - p_region.size.x",
            "p_region.position.y > data_depth - p_region.size.y",
            "int64_t(p_region.size.x) * int64_t(p_region.size.y) > 4096",
            "p_heights.size() != p_region.size.x * p_region.size.y",
            "!Math::is_finite(p_heights[i])",
            "return false",
            "if (!changed)",
            "height_data.ptrw()",
            "normal_data.ptrw()",
            "update_region(p_region)",
        ):
            self.assertIn(marker, fn)
        self.assertLess(fn.index("!Math::is_finite(p_heights[i])"),
                        fn.index("real_t *samples = height_data.ptrw()"))
        self.assertLess(fn.index("!data_from_script"),
                        fn.index("real_t *samples = height_data.ptrw()"))
        self.assertNotIn("_queue_rebuild()", fn)
        self.assertNotIn("set_height_data(", fn)

    def test_partial_chunk_lod_and_collision_invalidations(self):
        fn = self.cpp.split("void ChunkedTerrain3D::update_region(", 1)[1].split(
            "int ChunkedTerrain3D::get_visible_chunk_count()", 1
        )[0]
        for marker in (
            "p_region.grow(1)",
            "chunk_samples.intersects(grown)",
            "rs->free_rid(chunk.meshes[i])",
            "_free_collision(chunk)",
            "chunk.bounds = AABB",
            "chunk.lod_errors[0] = 0.0",
            "chunk_lod_max_error(_field()",
            "chunk.lod_errors[level] = MAX(error, chunk.lod_errors[level - 1])",
            "time_since_update = 1e9",
        ):
            self.assertIn(marker, fn)
        self.assertLess(fn.index("chunk_samples.intersects(grown)"),
                        fn.index("_free_collision(chunk)"))
        self.assertNotIn("_free_chunks()", fn)
        self.assertNotIn("_rebuild()", fn)

    def test_real_albion_streamed_terrain_and_manual_debug_tool(self):
        self.assertIn("_terrain = ChunkedTerrain3D.new()", self.chunk)
        self.assertIn("_terrain.set_height_data(heights, Vector2i(SAMPLES, SAMPLES))", self.chunk)
        self.assertIn("_terrain.add_to_group(TERRAIN_LOD_GROUP)", self.chunk)
        self.assertIn("_terrain.collision_enabled = false", self.chunk)
        self.assertIn('get_nodes_in_group("aa_chunked_terrain_lod")', self.game)
        self.assertIn('terrain.call("apply_height_patch",', self.game)
        self.assertIn('candidate.call("force_update")', self.game)
        self.assertIn("patch_size.x * patch_size.y > 4096", self.game)
        self.assertIn("if OS.is_debug_build()", self.online)
        self.assertIn("event.keycode == KEY_F9", self.online)
        self.assertIn("TerrainLivePatch.apply_to_streamed_world(", self.online)
        self.assertIn("event.ctrl_pressed and event.shift_pressed", self.online)
        self.assertIn("get_viewport().set_input_as_handled()", self.online)

    def test_native_and_game_regressions(self):
        for marker in (
            "Partial height patches keep far chunks and refresh geometric LOD errors",
            "Bad late patch samples reject the entire terrain transaction",
            "Partial patch updates custom normals near dirty samples",
            "get_collision_chunk_count() > 0",
            "get_chunk_lod_error(Vector2i(1, 1)",
            "float(Math::NaN)",
            "maximum.resize(4096)",
        ):
            self.assertIn(marker, self.native_tests)
        for marker in (
            "real Albion online client invokes the patch tool",
            "native terrain patch handles live cosmetic sculpting",
            "edited chunk recalculates its coarse mesh error",
            "cosmetic terrain editing does not create client-side collision",
            "invalid late sample rejects entire native edit",
            "group-based debug hotkey route edits an existing chunk instance",
        ):
            self.assertIn(marker, self.game_tests)
        self.assertIn('"res://tests/test_terrain_live_patch.gd"',
                      (ROOT / "game/tests/run_all.gd").read_text())

    def test_docs_and_ci(self):
        xml = ET.parse(ROOT / "doc/classes/ChunkedTerrain3D.xml").getroot()
        names = {m.get("name") for m in xml.findall("./methods/method")}
        self.assertIn("apply_height_patch", names)
        self.assertIn("get_chunk_lod_error", names)
        docs = (ROOT / "game/docs/p1_incremental_terrain_editing.md").read_text()
        self.assertIn("Unreal", docs)
        self.assertIn("not", docs.lower())
        workflow = (ROOT / ".github/workflows/native-terrain-partial-patches.yml").read_text()
        for marker in (
            "test_terrain_partial_patch_contract.py",
            "test_chunked_terrain_3d.cpp",
            "test_terrain_live_patch",
            'tests=yes module_text_server_fb_enabled=yes',
        ):
            self.assertIn(marker, workflow)


if __name__ == "__main__":
    unittest.main()
