"""P1 virtual geometry page ABI and actual Albion scene integration checks.

These source contracts are not native compilation or GPU validation.
"""
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
MODULE = ROOT / "modules/cgame_virtual_geometry"
GAME = ROOT / "game/scripts/client"


class TestMeshletPageContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.header = (MODULE / "cgame_meshlet_pages.h").read_text()
        cls.cpp = (MODULE / "cgame_meshlet_pages.cpp").read_text()
        cls.register = (MODULE / "register_types.cpp").read_text()
        cls.config = (MODULE / "config.py").read_text()
        cls.inspector = (GAME / "virtual_geometry_page_inspector.gd").read_text()
        cls.online = (GAME / "online_main.gd").read_text()
        cls.chunk = (GAME / "chunk_view.gd").read_text()
        cls.native_tests = (MODULE / "tests/test_cgame_meshlet_pages.h").read_text()
        cls.game_tests = (ROOT / "game/tests/test_virtual_geometry_meshlet_pages.gd").read_text()

    def test_registered_gpu_ready_page_format(self):
        self.assertIn("class CgameMeshletPages : public RefCounted", self.header)
        self.assertIn("static Array build_pages(", self.header)
        self.assertIn("static Dictionary inspect_page(", self.header)
        self.assertIn("GDREGISTER_CLASS(CgameMeshletPages)", self.register)
        self.assertIn('#include "cgame_meshlet_pages.h"', self.register)
        self.assertIn('"CgameMeshletPages"', self.config)
        for symbol in (
            'D_METHOD("build_pages", "vertices", "indices", "page_bytes")',
            'D_METHOD("inspect_page", "page")',
            'constexpr uint32_t PAGE_MAGIC = 0x504d4743u',
            'constexpr uint32_t PAGE_VERSION = 1',
            'constexpr int HEADER_BYTES = 32',
            'constexpr int DESCRIPTOR_BYTES = 48',
            'constexpr int MAX_PAGE_BYTES = 65536',
        ):
            self.assertIn(symbol, self.cpp + self.header)

    def test_bounded_le_layout_retains_source_global_vertex_references(self):
        source = self.cpp.split("Array CgameMeshletPages::build_pages(", 1)[1].split(
            "Dictionary CgameMeshletPages::inspect_page(", 1)[0]
        for needle in (
            "p_page_bytes < 1024",
            "p_page_bytes > MAX_PAGE_BYTES",
            "vertex_count > 1000000",
            "index_count > 3000000",
            "index_count % 3 != 0",
            "!vertex.is_finite()",
            "!Math::is_finite(x)",
            "p_indices[i] < 0 || p_indices[i] >= vertex_count",
            "CgameMeshlets::build_native(",
            "meshlets.size() && count < 128",
            "uint64_t(HEADER_BYTES)",
            "uint64_t(count + 1) * DESCRIPTOR_BYTES",
            "wanted > uint64_t(p_page_bytes)",
            "page.resize(total_bytes)",
            "put_u32(dst, 0, PAGE_MAGIC)",
            "put_u32(dst, 4, PAGE_VERSION)",
            "put_u32(dst, 28, total_bytes)",
            "put_u32(dst, current_vertex, uint32_t(meshlet.vertex_ids[j]))",
            "dst[current_triangle++] = uint8_t(local)",
            "first += count",
        ):
            self.assertIn(needle, source)
        self.assertLess(source.index("p_indices[i] < 0 || p_indices[i] >= vertex_count"),
                        source.index("CgameMeshlets::build_native("))
        self.assertNotIn("meshopt_simplify(", source)
        self.assertNotIn("RenderingDevice", source)

    def test_page_decode_fail_closed(self):
        source = self.cpp.split("Dictionary CgameMeshletPages::inspect_page(", 1)[1].split(
            "void CgameMeshletPages::_bind_methods(", 1)[0]
        for needle in (
            "get_u32(src, 0) != PAGE_MAGIC",
            "get_u32(src, 4) != PAGE_VERSION",
            "get_u32(src, 28) != uint32_t(size)",
            "count < 1 || count > 128",
            "vertices != desc + count * DESCRIPTOR_BYTES",
            "ref_count < 3 || ref_count > 64",
            "tris < 1 || tris > 124",
            "ref_offset != cursor_vertex || tri_offset != cursor_triangle",
            "id >= 1000000",
            "local >= ref_count",
            "!center.is_finite()",
            "!Math::is_finite(radius)",
            "!cone.is_finite()",
            "cursor_vertex != triangles || cursor_triangle != uint32_t(size)",
            'result["meshlets"] = meshlet_list',
        ):
            self.assertIn(needle, source)

    def test_real_game_intercepts_debug_hotkey_before_existing_f8_action(self):
        self.assertIn('instance.add_to_group(SCENERY_GROUP)', self.chunk)
        self.assertIn('const SCENERY_GROUP := "aa_scenery_multimeshes"', self.inspector)
        self.assertIn('get_nodes_in_group(SCENERY_GROUP)', self.inspector)
        self.assertIn("const MAX_SCANNED := 96", self.inspector)
        self.assertIn("var mesh: Mesh = instance.multimesh.mesh", self.inspector)
        self.assertIn('builder.call("build_pages", vertices, indices, max_page_bytes)', self.inspector)
        self.assertIn('builder.call("inspect_page", page)', self.inspector)
        self.assertIn("recovered != int(indices.size() / 3)", self.inspector)
        self.assertIn('ClassDB.class_exists("CgameMeshletPages")', self.inspector)
        self.assertIn("VirtualGeometryPageInspector.inspect_streamed_world(", self.online)
        self.assertIn("OS.is_debug_build() and event is InputEventKey", self.online)
        self.assertIn("event.ctrl_pressed and event.shift_pressed", self.online)
        self.assertIn("event.keycode == KEY_F8", self.online)
        self.assertIn("get_viewport().set_input_as_handled()", self.online)
        self.assertLess(self.online.index("VirtualGeometryPageInspector.inspect_streamed_world("),
                        self.online.index("client.parry()"))

    def test_native_coverage_game_material_regressions_and_docs(self):
        for needle in (
            "bounded binary pages retain every original triangle reference",
            "corrupted page byte counts offsets references and cones fail closed",
            "malformed source geometry is never partially serialized",
            "total_triangles == input.size() / 3",
            "reconstructed.size() == original.size()",
            "CgameMeshletPages::inspect_page(corrupt).is_empty()",
        ):
            self.assertIn(needle, self.native_tests)
        for needle in (
            "actual Albion outdoor scenery registers its MultiMesh nodes",
            "page descriptors reference every original triangle exactly once",
            "original full PBR streams and material remain untouched",
            "on-demand profiler sees loaded MultiMesh",
            "game level inspection reports correct actual geometry complexity",
        ):
            self.assertIn(needle, self.game_tests)
        self.assertIn('"res://tests/test_virtual_geometry_meshlet_pages.gd"',
                      (ROOT / "game/tests/run_all.gd").read_text())
        xml = ET.parse(MODULE / "doc_classes/CgameMeshletPages.xml").getroot()
        methods = {m.get("name") for m in xml.findall("./methods/method")}
        self.assertEqual(methods, {"build_pages", "inspect_page"})
        readme = (MODULE / "README.md").read_text()
        self.assertIn("P1 meshlet page payloads", readme)
        self.assertIn("not", readme.lower())
        workflow = (ROOT / ".github/workflows/native-meshlet-page-serialization.yml").read_text()
        for needle in (
            "test_meshlet_page_contract.py",
            "*CgameMeshletPages*",
            "test_virtual_geometry_meshlet_pages",
            "test_virtual_geometry_attribute_lod",
            "tests=yes module_text_server_fb_enabled=yes",
        ):
            self.assertIn(needle, workflow)


if __name__ == "__main__":
    unittest.main()
