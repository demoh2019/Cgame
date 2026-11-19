#!/usr/bin/env python3
"""Source regression contracts for Godot upstream #119021 and #124098.

These are fast source guards, not substitutes for native import and rendering
tests. The native tests live in tests/scene/test_arraymesh.cpp.
"""
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[3]


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class ObjImporterGuards(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.obj = read("editor/import/3d/resource_importer_obj.cpp")
        cls.tests = read("tests/scene/test_arraymesh.cpp")

    def test_kd_color_conversion_is_conditional(self):
        self.assertIn("current->set_albedo(p_linear_diffuse_color ? c.linear_to_srgb() : c);", self.obj)

    def test_kd_reads_three_material_color_components(self):
        block = self.obj.split('} else if (l.begins_with("Kd ")) {', 1)[1].split('} else if (l.begins_with("Ks ")) {', 1)[0]
        for component in ("c.r = v[1].to_float();", "c.g = v[2].to_float();", "c.b = v[3].to_float();"):
            with self.subTest(component=component):
                self.assertIn(component, block)

    def test_alpha_parsing_remains_separate(self):
        self.assertIn('} else if (l.begins_with("d ")) {', self.obj)
        self.assertIn('} else if (l.begins_with("Tr ")) {', self.obj)

    def test_linear_import_option_defaults_to_legacy(self):
        self.assertIn('ImportOption(PropertyInfo(Variant::BOOL, "materials/mtl_diffuse_is_linear"), false)', self.obj)

    def test_missing_import_option_defaults_to_false(self):
        self.assertEqual(self.obj.count('linear_option && bool(*linear_option)'), 2)

    def test_both_import_entry_points_forward_mode(self):
        self.assertIn('_parse_material_library(lib_path, lib, r_missing_deps, p_linear_diffuse_color);', self.obj)
        self.assertIn('mesh_lightmap_caches, r_missing_deps, linear_diffuse_color);', self.obj)
        self.assertIn('mesh_lightmap_caches, nullptr, linear_diffuse_color);', self.obj)

    def test_native_obj_fixture_checks_legacy_and_linear_modes(self):
        self.assertIn("for (int mode = 0; mode < 3; mode++)", self.tests)
        self.assertIn('options[StringName("materials/mtl_diffuse_is_linear")] = (mode == 2);', self.tests)

    def test_native_obj_import_fixture_is_present(self):
        self.assertIn("MTL diffuse color defaults to legacy and supports linear opt-in", self.tests)
        self.assertIn("EditorOBJImporter *importer = memnew(EditorOBJImporter);", self.tests)

    def test_native_obj_fixture_checks_color(self):
        self.assertIn("const Color expected = mode == 2 ? stored_color.linear_to_srgb() : stored_color;", self.tests)
        self.assertIn("material->get_albedo().is_equal_approx(expected)", self.tests)

    def test_obj_fixture_is_multiline(self):
        self.assertIn(r'newmtl ImportedMaterial\nKd 0.5 0.25 1.0\n', self.tests)
        self.assertIn(r'usemtl ImportedMaterial\nv 0 0 0\n', self.tests)


class ImporterMeshGuards(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.mesh = read("scene/resources/3d/importer_mesh.cpp")
        cls.header = read("scene/resources/mesh.h")
        cls.tests = read("tests/scene/test_arraymesh.cpp")
        cls.func = cls.mesh.split("Ref<ArrayMesh> ImporterMesh::get_mesh", 1)[1].split("Ref<ImporterMesh> ImporterMesh::from_mesh", 1)[0]

    def test_arraymesh_gives_importer_friend_access(self):
        self.assertIn("friend class ImporterMesh;", self.header)

    def test_change_signal_is_blocked_before_mesh_modification(self):
        self.assertLess(self.func.index("mesh->_block_emit_changed();"), self.func.index("mesh->set_name(get_name());"))

    def test_change_signal_is_unblocked_after_surface_creation(self):
        self.assertLess(self.func.index("mesh->add_surface_from_arrays"), self.func.index("mesh->_unblock_emit_changed();"))

    def test_change_signal_is_unblocked_after_shadow_mesh(self):
        self.assertLess(self.func.index("mesh->set_shadow_mesh(shadow)"), self.func.index("mesh->_unblock_emit_changed();"))

    def test_mesh_is_not_rebuilt_if_cached(self):
        self.assertIn("if (mesh.is_null())", self.func)

    def test_native_signal_test_checks_single_emit(self):
        self.assertIn("Imported ArrayMesh emits changed once after all surfaces", self.tests)
        self.assertIn('SIGNAL_WATCH(base.ptr(), "changed")', self.tests)
        self.assertIn('SIGNAL_CHECK("changed", expected_signal_args)', self.tests)
        self.assertIn('SIGNAL_UNWATCH(base.ptr(), "changed")', self.tests)

    def test_native_signal_test_covers_multiple_surface_counts(self):
        self.assertIn("for (int surface_count : { 1, 2, 4 })", self.tests)


if __name__ == "__main__":
    unittest.main()
