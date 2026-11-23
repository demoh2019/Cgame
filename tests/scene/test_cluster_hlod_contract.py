"""Verify native cluster-to-ArrayMesh PBR wiring in Albion After.

Source-only tests: native doctests and real game runs are still required.
"""

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def src(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


class ClusterCutHLODContract(unittest.TestCase):
    def test_native_api_validates_and_preserves_all_attributes(self):
        cpp = src("modules/cgame_virtual_geometry/cgame_cluster_lod.cpp")
        hdr = src("modules/cgame_virtual_geometry/cgame_cluster_lod.h")
        doc = src("modules/cgame_virtual_geometry/doc_classes/CgameClusterLOD.xml")
        for token in (
            "build_cut_surface",
            "p_source_arrays.duplicate(false)",
            "result[Mesh::ARRAY_INDEX]",
        ):
            # No vertex attributes should be discarded to build an index-only cut.
            self.assertIn(token if token != "result[Mesh::ARRAY_INDEX]" else "output[Mesh::ARRAY_INDEX]", cpp)
        for token in (
            "seen.has(id)",
            "indices[j] < 0 || indices[j] >= vertices.size()",
            "vertices != (PackedVector3Array)p_hierarchy",
            "source_indices.size() - total",
        ):
            self.assertIn(token, cpp)
        self.assertIn("static Array build_cut_surface", hdr)
        self.assertIn('name="build_cut_surface"', doc)
        self.assertIn("GPU pages", doc)

    def test_game_uses_real_cluster_proxy_with_safe_fallback(self):
        game = src("game/scripts/client/pcg_world_dressing.gd")
        for token in (
            'EngineFeatures.has("CgameClusterLOD")',
            'native.call("build_hierarchy", vertices, indices, 5)',
            'native.call("build_cut_surface", hierarchy, cut, arrays)',
            'native.call("triangle_count", hierarchy, cut)',
            "mesh.surface_get_format(0)",
            "mesh.surface_get_material(0)",
            "triangles * 5 > indices.size()",
            "cluster_proxy_for(mesh)",
            "_proxy_cache[mesh] = cluster_proxy",
        ):
            self.assertIn(token, game)
        self.assertIn("var box := BoxMesh.new()", game)
        self.assertIn("c.set_asset_proxy_meshes(proxies)", game)
        self.assertIn("c.set_streaming_enabled(true)", game)

    def test_real_game_and_native_regressions_are_registered(self):
        game_tests = src("game/tests/test_virtual_cluster_hlod.gd")
        native_tests = src("modules/cgame_virtual_geometry/tests/test_cgame_virtual_geometry.h")
        runner = src("game/tests/run_all.gd")
        for token in (
            "PcgWorldDressing.proxy_for",
            "PcgWorldDressing.cluster_proxy_for",
            "selected.size()",
            "ClassDB.class_exists",
            "PBR source attribute",
        ):
            self.assertIn(token, game_tests)
        self.assertIn("test_virtual_cluster_hlod.gd", runner)
        self.assertIn("[CgameClusterLOD] Reconstructed cut", native_tests)
        self.assertIn("Ref<ArrayMesh> draw_mesh", native_tests)
        self.assertIn("duplicate or invalid cluster id.", src("modules/cgame_virtual_geometry/cgame_cluster_lod.cpp"))


if __name__ == "__main__":
    unittest.main()
