"""P1 virtual geometry: native weighted simplification and real Albion PBR path.

Structural checks complement (do not replace) native compile and game runtime CI.
"""
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
MODULE = ROOT / "modules/cgame_virtual_geometry"
GAME = ROOT / "game/scripts/client"


class TestVirtualGeometryAttributeContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.header = (MODULE / "cgame_cluster_lod.h").read_text()
        cls.cpp = (MODULE / "cgame_cluster_lod.cpp").read_text()
        cls.mesh_lod = (GAME / "mesh_lod_preservation.gd").read_text()
        cls.model = (GAME / "model_catalog.gd").read_text()
        cls.native_tests = (MODULE / "tests/test_cgame_virtual_geometry.h").read_text()
        cls.game_tests = (ROOT / "game/tests/test_virtual_geometry_attribute_lod.gd").read_text()

    def test_registered_native_surface_api(self):
        self.assertIn("static Array simplify_surface_arrays(", self.header)
        self.assertIn("Array CgameClusterLOD::simplify_surface_arrays(", self.cpp)
        self.assertIn('D_METHOD("simplify_surface_arrays",', self.cpp)
        self.assertIn("DEFVAL(0.6f), DEFVAL(0.6f)", self.cpp)
        self.assertIn('#include "scene/resources/mesh.h"', self.cpp)

    def test_attribute_and_input_validation_before_simplification(self):
        fn = self.cpp.split(
            "Array CgameClusterLOD::simplify_surface_arrays(", 1
        )[1].split("void CgameClusterLOD::_bind_methods(", 1)[0]
        for needle in (
            "p_surface_arrays.size() != Mesh::ARRAY_MAX",
            "Variant::PACKED_VECTOR3_ARRAY",
            "Variant::PACKED_INT32_ARRAY",
            "p_target_triangles >= index_count / 3",
            "vertex_count > 1000000",
            "index_count > 3000000",
            "Math::is_finite(p_normal_weight)",
            "Math::is_finite(p_uv_weight)",
            "p_normal_weight > 8.0f",
            "p_uv_weight > 8.0f",
            "normals.size() != vertex_count",
            "uvs.size() != vertex_count",
            "!src_vertices[i].is_finite()",
            "!src_normals[i].is_finite()",
            "!src_uvs[i].is_finite()",
            "indices[i] < 0 || indices[i] >= vertex_count",
        ):
            self.assertIn(needle, fn)
        self.assertLess(fn.index("indices[i] < 0 || indices[i] >= vertex_count"),
                        fn.index("meshopt_simplifyWithAttributes("))

    def test_weighted_meshopt_retains_original_vertex_streams(self):
        fn = self.cpp.split(
            "Array CgameClusterLOD::simplify_surface_arrays(", 1
        )[1].split("void CgameClusterLOD::_bind_methods(", 1)[0]
        for needle in (
            "meshopt_simplifyWithAttributes(",
            "meshopt_SimplifyLockBorder | meshopt_SimplifyErrorAbsolute",
            "meshopt_simplify(destination.ptr()",
            "const Vector3 *src_normals",
            "const Vector2 *src_uvs",
            "p_normal_weight",
            "p_uv_weight",
            "LocalVector<uint32_t> src_indices",
            "Array result = p_surface_arrays.duplicate()",
            "result[Mesh::ARRAY_INDEX] = reduced;",
        ):
            self.assertIn(needle, fn)
        self.assertNotIn("result[Mesh::ARRAY_NORMAL] =", fn)
        self.assertNotIn("result[Mesh::ARRAY_VERTEX] =", fn)
        self.assertNotIn("result[Mesh::ARRAY_TEX_UV] =", fn)
        self.assertNotIn("RenderingServer", fn)
        self.assertNotIn("PhysicsServer", fn)

    def test_actual_cached_model_catalog_uses_opt_in_native_path(self):
        self.assertIn(
            "MeshLOD.with_generated_lods(MeshLOD.with_triangle_budget(", self.model)
        self.assertIn("static func with_native_attribute_budget(", self.mesh_lod)
        self.assertIn('ClassDB.class_exists("CgameClusterLOD")', self.mesh_lod)
        self.assertIn('native.has_method("simplify_surface_arrays")', self.mesh_lod)
        self.assertIn('native.call("simplify_surface_arrays",', self.mesh_lod)
        self.assertIn("with_native_attribute_budget(source, max_triangles)", self.mesh_lod)
        self.assertIn("var generated := ImporterMesh.new()", self.mesh_lod)
        self.assertIn("result.surface_set_material(0, mesh.surface_get_material(0))",
                      self.mesh_lod)
        self.assertIn("result.custom_aabb = (mesh as ArrayMesh).custom_aabb", self.mesh_lod)
        self.assertIn("result.resource_name = mesh.resource_name", self.mesh_lod)

    def test_native_and_real_game_regressions(self):
        for needle in (
            "attribute aware surface simplification preserves authored channels",
            "attribute simplification rejects malformed late data atomically",
            "Mesh::ARRAY_TEX_UV2",
            "Mesh::ARRAY_TANGENT",
            "Math::NaN",
            "Math::INF",
        ):
            self.assertIn(needle, self.native_tests)
        for needle in (
            "native meshopt weighted normals UV and non-destructive PBR fidelity",
            "authored PBR/tangent/UV2/painted surface stream is preserved exactly",
            "actual Albion MultiMesh prop bake preserves material and source vertex streams",
            "real game mesh retains imported vertex attributes",
            "production model-catalog triangle budget uses the new native feature",
        ):
            self.assertIn(needle, self.game_tests)
        self.assertIn('"res://tests/test_virtual_geometry_attribute_lod.gd"',
                      (ROOT / "game/tests/run_all.gd").read_text())

    def test_xml_docs_and_ci(self):
        xml = ET.parse(MODULE / "doc_classes/CgameClusterLOD.xml").getroot()
        methods = {m.get("name") for m in xml.findall("./methods/method")}
        self.assertIn("simplify_surface_arrays", methods)
        self.assertIn("attribute-fidelity", (MODULE / "README.md").read_text().lower())
        notes = (ROOT / "game/docs/p1_nanite_attribute_preservation.md").read_text()
        self.assertIn("Unreal Engine Nanite", notes)
        self.assertIn("not yet", notes.lower())
        ci = (ROOT / ".github/workflows/native-virtual-geometry-attribute-lod.yml").read_text()
        for marker in (
            "test_virtual_geometry_attribute_contract.py",
            "*CgameClusterLOD*attribute*",
            "test_virtual_geometry_attribute_lod",
            "test_mesh_pbr_preservation",
            "tests=yes module_text_server_fb_enabled=yes",
        ):
            self.assertIn(marker, ci)


if __name__ == "__main__":
    unittest.main()
