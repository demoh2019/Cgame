"""Source-level regression checks for upstream Godot cleanup backports.

These tests verify critical control-flow invariants when external display
creation or OpenXR cleanup fails. They are not a replacement for engine builds,
hardware XR tests or platform integration tests.
"""

from __future__ import annotations

from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
MAIN = ROOT / "main/main.cpp"
XR = ROOT / "modules/openxr/extensions/spatial_container/openxr_spatial_container_extension.cpp"
XR_RENDER = ROOT / "modules/openxr/extensions/spatial_container/openxr_spatial_container_self_rendering_extension.cpp"


def function_body(file: Path, signature: str) -> str:
    text = file.read_text(encoding="utf-8")
    start = text.index(signature)
    begin = text.index("{", start)
    depth = 0
    for offset in range(begin, len(text)):
        if text[offset] == "{":
            depth += 1
        elif text[offset] == "}":
            depth -= 1
            if depth == 0:
                return text[begin + 1:offset]
    raise AssertionError(f"Unclosed function {signature}")


class DisplayStartupFailureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        text = MAIN.read_text(encoding="utf-8")
        begin = text.index('ERR_PRINT("Unable to create DisplayServer')
        end = text.index("return err;", begin)
        cls.failure = text[begin:end]

    def test_uses_shared_display_cleanup_not_direct_delete(self):
        self.assertIn("finalize_display();", self.failure)
        self.assertNotIn("memdelete(display_server);", self.failure)

    def test_cleanup_before_extension_deinitialize(self):
        self.assertLess(self.failure.index("finalize_display();"),
                        self.failure.index("deinitialize_extensions("))

    def test_navigation_2d_manager_finalized(self):
        self.assertIn("NavigationServer2DManager::finalize_server_manager();", self.failure)
        self.assertRegex(self.failure, r"#ifndef NAVIGATION_2D_DISABLED\s+NavigationServer2DManager::finalize_server_manager\(\);")

    def test_navigation_3d_manager_finalized(self):
        self.assertIn("NavigationServer3DManager::finalize_server_manager();", self.failure)
        self.assertRegex(self.failure, r"#ifndef NAVIGATION_3D_DISABLED\s+NavigationServer3DManager::finalize_server_manager\(\);")

    def test_navigation_before_extension_deinit(self):
        i = self.failure.index("deinitialize_extensions(")
        for name in ("NavigationServer2DManager", "NavigationServer3DManager"):
            self.assertLess(self.failure.index(name + "::finalize_server_manager();"), i)

    def test_server_modules_and_types_still_uninitialized(self):
        self.assertIn("uninitialize_modules(MODULE_INITIALIZATION_LEVEL_SERVERS);", self.failure)
        self.assertIn("unregister_server_types();", self.failure)

    def test_existing_physics_cleanup_preserved(self):
        self.assertIn("PhysicsServer2DManager::finalize_server_manager();", self.failure)
        self.assertIn("PhysicsServer3DManager::finalize_server_manager();", self.failure)


class SpatialContainerCleanupTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.close = function_body(XR, "void OpenXRSpatialContainerExtension::destroy_spatial_container(")
        cls.remove = function_body(XR_RENDER, "void OpenXRSpatialContainerSelfRenderingExtension::_remove_spatial_container_from_render_set(")

    def test_container_cleanup_guarded_by_active_state(self):
        self.assertIn("if (is_spatial_container_active())", self.close)

    def test_optional_openxr_api_does_not_abort_destruction(self):
        self.assertIn("if (openxr_api)", self.close)
        self.assertNotIn("ERR_FAIL_NULL(OpenXRAPI::get_singleton())", self.close)
        self.assertIn("xrDestroySpatialContainerEXT", self.close)
        self.assertLess(self.close.index("if (openxr_api)"), self.close.index("xrDestroySpatialContainerEXT"))

    def test_destroy_failure_does_not_return_before_local_cleanup(self):
        begin = self.close.index("if (XR_FAILED(result))")
        end = self.close.index("spatial_container_data.spatial_container_handle = XR_NULL_HANDLE;", begin)
        failed = self.close[begin:end]
        self.assertIn('ERR_PRINT("Failed to destroy spatial container.");', failed)
        self.assertNotRegex(failed, r"\breturn\s*;")

    def test_container_handles_reset_even_on_destroy_error(self):
        self.assertIn("spatial_container_data.spatial_container_handle = XR_NULL_HANDLE;", self.close)
        self.assertIn("spatial_container_data.space_handle = XR_NULL_HANDLE;", self.close)

    def test_container_rid_is_freed_even_on_destroy_error(self):
        self.assertIn("spatial_container_owner.free(spatial_container_data.spatial_container_rid);", self.close)
        self.assertIn("spatial_container_data.spatial_container_rid = RID();", self.close)

    def test_render_set_already_inactive_does_not_call_runtime(self):
        self.assertIn("if (active_spatial_container != p_container)", self.remove)
        self.assertIn("return;", self.remove.split("if (active_spatial_container != p_container)", 1)[1].split("}", 1)[0])

    def test_missing_openxr_api_skips_only_runtime_call(self):
        self.assertIn("if (openxr_api)", self.remove)
        self.assertNotIn("ERR_FAIL_NULL(openxr_api)", self.remove)
        self.assertIn("xrEndSpatialContainerRenderingEXT", self.remove)

    def test_runtime_end_error_does_not_skip_render_state_reset(self):
        pos = self.remove.index("if (XR_FAILED(result))")
        reset = self.remove.index("active_spatial_container = XR_NULL_HANDLE;", pos)
        self.assertNotRegex(self.remove[pos:reset], r"\breturn\s*;")
        self.assertIn("ERR_PRINT", self.remove[pos:reset])

    def test_render_state_clears_layer_and_view_refs(self):
        for expression in (
            "active_view_state.viewStateFlags = 0;",
            "active_view_state.shouldSubmitLayers = false;",
            "active_layer.spatialContainer = XR_NULL_HANDLE;",
            "active_layer.layerCount = 0;",
            "active_layer.layers = nullptr;",
        ):
            with self.subTest(expression=expression):
                self.assertIn(expression, self.remove)


if __name__ == "__main__":
    unittest.main()
