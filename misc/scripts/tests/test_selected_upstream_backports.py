"""Source-contract regressions for selectively ported upstream Godot PRs.

These checks are fast CI guards, NOT a replacement for compiling Godot and
running tests/scene/test_instance_shader_parameters.cpp on a native build.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
LOD = ROOT / "scene/resources/3d/importer_mesh.cpp"
SURFACE_TOOL = ROOT / "scene/resources/surface_tool.h"
VIEWPORT = ROOT / "servers/rendering/renderer_viewport.cpp"
CANVAS = ROOT / "scene/main/canvas_item.cpp"
GEOMETRY = ROOT / "scene/3d/visual_instance_3d.cpp"
UNIFORMS = ROOT / "servers/rendering/instance_uniforms.cpp"
NATIVE_TEST = ROOT / "tests/scene/test_instance_shader_parameters.cpp"


def read(path):
    return path.read_text(encoding="utf-8")


def body(source, start, end):
    """Inspect the production function rather than an unrelated mention."""
    a = source.index(start)
    b = source.index(end, a + len(start))
    return source[a:b]


class LODAttributeRegressionTests(unittest.TestCase):
    """godotengine/godot#125582 — avoid excessive attribute LOD error."""

    def test_meshoptimizer_option_is_available(self):
        self.assertIn("SIMPLIFY_ERROR_CLAMPED = 1 << 8", read(SURFACE_TOOL))

    def test_importer_enables_error_clamping(self):
        region = body(read(LOD), "int simplify_options = SurfaceTool::SIMPLIFY_SPARSE",
                      "SurfaceTool::simplify_with_attrib_func(")
        self.assertIn("simplify_options |= SurfaceTool::SIMPLIFY_ERROR_CLAMPED;", region)

    def test_flag_precedes_attribute_simplification(self):
        region = body(read(LOD), "int simplify_options = SurfaceTool::SIMPLIFY_SPARSE",
                      "SurfaceTool::simplify_with_attrib_func(")
        self.assertLess(region.index("SIMPLIFY_ERROR_CLAMPED"),
                        region.index("SIMPLIFY_LOCK_BORDER"))

    def test_existing_lod_constraints_preserved(self):
        region = body(read(LOD), "int simplify_options = SurfaceTool::SIMPLIFY_SPARSE",
                      "SurfaceTool::simplify_with_attrib_func(")
        for required in ("SIMPLIFY_SPARSE", "SIMPLIFY_LOCK_BORDER",
                         "SIMPLIFY_PRUNE", "SIMPLIFY_REGULARIZE"):
            with self.subTest(required=required):
                self.assertIn(required, region)


class XRVRSSafetyTests(unittest.TestCase):
    """godotengine/godot#125555 — no unwritten density map in flat mode."""

    def setUp(self):
        self.source = read(VIEWPORT)
        self.method = body(self.source, "void RendererViewport::viewport_set_vrs_mode(",
                           "void RendererViewport::viewport_set_vrs_update_mode(")

    def test_requires_xr_mode_before_fallback(self):
        self.assertIn("if (p_mode == RSE::VIEWPORT_VRS_XR)", self.method)

    def test_handles_builds_without_xr(self):
        self.assertRegex(self.method, r"#ifndef XR_DISABLED\s*xr_possible =")
        self.assertIn("#endif // XR_DISABLED", self.method)

    def test_runtime_xr_off_detection(self):
        self.assertIn("XRServer::get_xr_mode() != XRServer::XRMODE_OFF", self.method)

    def test_disabled_mode_applied_before_renderer(self):
        self.assertIn("p_mode = RSE::VIEWPORT_VRS_DISABLED;", self.method)
        self.assertLess(self.method.index("p_mode = RSE::VIEWPORT_VRS_DISABLED;"),
                        self.method.index("render_target_set_vrs_mode("))

    def test_fallback_does_not_change_other_modes(self):
        self.assertRegex(self.method, r"if \(p_mode == RSE::VIEWPORT_VRS_XR\)")

    def test_xr_header_available(self):
        self.assertIn('#include "servers/xr/xr_server.h"', self.source)


class InstanceShaderPersistenceTests(unittest.TestCase):
    """godotengine/godot#125565 — preserve shader overrides while unresolved."""

    @staticmethod
    def functions(source, kind):
        getter = body(source, "bool " + kind + "::_get(", "void " + kind + "::_get_property_list(")
        props = body(source, "void " + kind + "::_get_property_list(",
                     "bool " + kind + "::_property_can_revert(" if kind == "GeometryInstance3D"
                     else "#ifdef TOOLS_ENABLED\nbool CanvasItem::_property_can_revert(")
        return getter, props

    def test_both_nodes_keep_resource_objects(self):
        for file, cls in [(CANVAS, "CanvasItem"), (GEOMETRY, "GeometryInstance3D")]:
            with self.subTest(node=cls):
                getter, _ = self.functions(read(file), cls)
                self.assertIn("instance_shader_parameters.getptr(*r)", getter)
                self.assertIn("Variant::OBJECT", getter)
                self.assertIn("? *stored : get_instance_shader_parameter(*r)", getter)

    def test_both_nodes_keep_resolved_properties_in_inspector(self):
        for file, cls in [(CANVAS, "CanvasItem"), (GEOMETRY, "GeometryInstance3D")]:
            with self.subTest(node=cls):
                _, props = self.functions(read(file), cls)
                self.assertIn("PropertyInfo pi_out = pi;", props)
                self.assertIn("p_list->push_back(pi_out);", props)

    def test_both_nodes_serialize_unresolved_override(self):
        for file, cls in [(CANVAS, "CanvasItem"), (GEOMETRY, "GeometryInstance3D")]:
            with self.subTest(node=cls):
                _, props = self.functions(read(file), cls)
                self.assertIn("for (const KeyValue<StringName, Variant> &E : instance_shader_parameters)", props)
                self.assertIn('PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE', props)

    def test_both_nodes_do_not_duplicate_live_shader_parameters(self):
        for file, cls in [(CANVAS, "CanvasItem"), (GEOMETRY, "GeometryInstance3D")]:
            with self.subTest(node=cls):
                _, props = self.functions(read(file), cls)
                self.assertIn("if (pi.name == E.key)", props)
                self.assertRegex(props, r"if \(exposed\) \{\s*continue;")

    def test_unresolved_property_type_comes_from_stored_value(self):
        for file in [CANVAS, GEOMETRY]:
            with self.subTest(file=file.name):
                self.assertIn("PropertyInfo(E.value.get_type()", read(file))

    def test_owning_nodes_take_over_unresolved_serialization(self):
        self.assertIn("owning nodes", read(UNIFORMS))

    def test_native_regressions_are_compiled_by_test_suite(self):
        source = read(NATIVE_TEST)
        self.assertIn("TEST_FORCE_LINK(test_instance_shader_parameters)", source)
        self.assertEqual(source.count("TEST_CASE("), 10)

    def test_native_test_covers_both_node_kinds(self):
        source = read(NATIVE_TEST)
        self.assertGreaterEqual(source.count('TEST_CASE("[InstanceShaderParameters] 2D'), 5)
        self.assertGreaterEqual(source.count('TEST_CASE("[InstanceShaderParameters] 3D'), 5)

    def test_native_test_covers_roundtrip_and_texture_types(self):
        source = read(NATIVE_TEST)
        for expected in ("packed->pack(", "packed->instantiate()",
                         "Variant::OBJECT", "Ref<ImageTexture>",
                         "PROPERTY_USAGE_STORAGE", "PROPERTY_USAGE_EDITOR"):
            with self.subTest(expected=expected):
                self.assertIn(expected, source)


if __name__ == "__main__":
    unittest.main()
