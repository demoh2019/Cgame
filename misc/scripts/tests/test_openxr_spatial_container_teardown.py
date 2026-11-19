#!/usr/bin/env python3
"""Source-level OpenXR spatial-container teardown regression contracts.

The real engine files are inspected. These tests are NOT XR runtime tests.
"""

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
CONTAINER = ROOT / "modules/openxr/extensions/spatial_container/openxr_spatial_container_extension.cpp"
SELF_RENDER = ROOT / "modules/openxr/extensions/spatial_container/openxr_spatial_container_self_rendering_extension.cpp"


def block_after(source: str, signature: str) -> str:
    start = source.index(signature)
    begin = source.index("{", start)
    depth = 0
    for i in range(begin, len(source)):
        if source[i] == "{":
            depth += 1
        elif source[i] == "}":
            depth -= 1
            if depth == 0:
                return source[begin + 1 : i]
    raise AssertionError("Unterminated C++ block after: " + signature)


class SpatialContainerDestructionContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.code = block_after(CONTAINER.read_text(encoding="utf-8"),
                               "void OpenXRSpatialContainerExtension::destroy_spatial_container()")

    def test_only_acts_on_active_container(self):
        self.assertIn("if (is_spatial_container_active())", self.code)

    def test_visibility_request_precedes_destroy(self):
        self.assertLess(self.code.index("request_spatial_container_visible(false)"),
                        self.code.index("xrDestroySpatialContainerEXT("))

    def test_rendering_mechanism_is_notified(self):
        self.assertIn("rendering_mechanism->on_spatial_container_closed(spatial_container_data)", self.code)

    def test_missing_openxr_api_cannot_abort_destructor(self):
        self.assertNotIn("ERR_FAIL_NULL(OpenXRAPI::get_singleton())", self.code)
        self.assertIn("OpenXRAPI *openxr_api = OpenXRAPI::get_singleton();", self.code)
        guarded = block_after(self.code, "if (openxr_api)")
        self.assertIn("set_custom_play_space(XR_NULL_HANDLE)", guarded)
        self.assertNotIn("xrDestroySpatialContainerEXT(", guarded)

    def test_destroy_attempt_occurs_even_without_api_singleton(self):
        guarded = block_after(self.code, "if (openxr_api)")
        self.assertLess(self.code.index("if (openxr_api)"), self.code.index("xrDestroySpatialContainerEXT("))
        self.assertNotIn("return;", self.code)

    def test_failed_xr_destroy_is_logged_and_nonfatal_for_cleanup(self):
        self.assertNotIn("ERR_FAIL_COND_MSG(XR_FAILED(result)", self.code)
        failure = block_after(self.code, "if (XR_FAILED(result))")
        self.assertIn('ERR_PRINT("Failed to destroy spatial container.")', failure)
        self.assertNotIn("return;", failure)

    def test_both_openxr_handles_reset_on_cleanup(self):
        self.assertIn("spatial_container_data.spatial_container_handle = XR_NULL_HANDLE;", self.code)
        self.assertIn("spatial_container_data.space_handle = XR_NULL_HANDLE;", self.code)

    def test_owner_rid_is_released_and_reset(self):
        self.assertIn("spatial_container_owner.free(spatial_container_data.spatial_container_rid);", self.code)
        self.assertIn("spatial_container_data.spatial_container_rid = RID();", self.code)

    def test_rid_cleanup_happens_after_xr_destroy_attempt(self):
        self.assertLess(self.code.index("xrDestroySpatialContainerEXT("),
                        self.code.index("spatial_container_owner.free("))


class SelfRenderingTeardownContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.code = block_after(
            SELF_RENDER.read_text(encoding="utf-8"),
            "void OpenXRSpatialContainerSelfRenderingExtension::_remove_spatial_container_from_render_set(")

    def test_unrelated_container_stays_untouched(self):
        other = block_after(self.code, "if (active_spatial_container != p_container)")
        self.assertIn("return;", other)

    def test_missing_api_does_not_abort_state_reset(self):
        self.assertNotIn("ERR_FAIL_NULL(openxr_api)", self.code)
        guarded = block_after(self.code, "if (openxr_api)")
        self.assertIn("xrEndSpatialContainerRenderingEXT(", guarded)
        self.assertNotIn("active_spatial_container = XR_NULL_HANDLE", guarded)

    def test_end_rendering_error_is_logged_not_returned(self):
        fail = block_after(self.code, "if (XR_FAILED(result))")
        self.assertIn('ERR_PRINT("OpenXR: Failed to end spatial container rendering.")', fail)
        self.assertNotIn("return;", fail)

    def test_state_reset_is_after_optional_api_call(self):
        self.assertLess(self.code.index("if (openxr_api)"),
                        self.code.index("active_spatial_container = XR_NULL_HANDLE"))

    def test_active_container_cleared(self):
        self.assertIn("active_spatial_container = XR_NULL_HANDLE;", self.code)

    def test_view_configuration_reset(self):
        self.assertIn("active_view_state.viewConfigurationType = XR_VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO;", self.code)
        self.assertIn("active_view_state.viewStateFlags = 0;", self.code)
        self.assertIn("active_view_state.shouldSubmitLayers = false;", self.code)

    def test_layer_payload_reset(self):
        for line in ("active_layer.spatialContainer = XR_NULL_HANDLE;",
                     "active_layer.retainPreviousSubmission = false;",
                     "active_layer.layerCount = 0;",
                     "active_layer.layers = nullptr;"):
            with self.subTest(line=line):
                self.assertIn(line, self.code)

    def test_error_cannot_leave_stale_active_layers(self):
        failure = self.code.index("if (XR_FAILED(result))")
        self.assertLess(failure, self.code.index("active_view_state.shouldSubmitLayers = false"))
        self.assertLess(failure, self.code.index("active_layer.layers = nullptr"))

    def test_only_valid_early_return_is_unrelated_container(self):
        other = block_after(self.code, "if (active_spatial_container != p_container)")
        self.assertEqual(self.code.count("return;"), other.count("return;"))



class FoveationPropertyChainContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = (ROOT / "modules/openxr/extensions/openxr_fb_foveation_extension.cpp").read_text(encoding="utf-8")
        cls.code = block_after(cls.source, "void *OpenXRFBFoveationExtension::set_system_properties_and_get_next_pointer(")

    def test_metaspecific_struct_requires_extension(self):
        self.assertIn('rendering_driver == "vulkan" && meta_foveation_eye_tracked_ext', self.code)

    def test_vulkan_only_chain_is_conditionally_compiled(self):
        self.assertIn("#ifdef XR_USE_GRAPHICS_API_VULKAN", self.code)
        self.assertIn("#endif", self.code)

    def test_next_pointer_chaining_only_occurs_in_checked_branch(self):
        guarded = block_after(self.code, 'if (rendering_driver == "vulkan" && meta_foveation_eye_tracked_ext)')
        self.assertIn("meta_foveation_eye_tracked_properties.next = p_next_pointer", guarded)
        self.assertIn("return &meta_foveation_eye_tracked_properties;", guarded)

    def test_plain_return_without_extension(self):
        self.assertIn("return p_next_pointer;", self.code)

    def test_metaspecific_properties_not_chained_unconditionally(self):
        self.assertEqual(self.code.count("meta_foveation_eye_tracked_properties.next ="), 1)


if __name__ == "__main__":
    unittest.main()
