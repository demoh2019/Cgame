"""Regression contracts for upstream Godot PRs #125553, #125558, #125552.

These source-level guards complement (and do not replace) native renderer
integration tests on GLES3, Vulkan, and Android/mobile devices.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
ALPHA_SOURCE = ROOT / "servers/rendering/renderer_rd/forward_mobile/scene_shader_forward_mobile.cpp"
GLES_SOURCE = ROOT / "drivers/gles3/storage/material_storage.cpp"
RD_SOURCE = ROOT / "servers/rendering/renderer_rd/storage_rd/material_storage.cpp"
VULKAN_SOURCE = ROOT / "drivers/vulkan/rendering_device_driver_vulkan.cpp"


def source(path):
    return path.read_text(encoding="utf-8")


def function_body(path, start, end):
    text = source(path)
    return text.split(start, 1)[1].split(end, 1)[0]


def allocate(path):
    return function_body(
        path, "int32_t MaterialStorage::global_shader_parameters_instance_allocate(",
        "void MaterialStorage::global_shader_parameters_instance_free(",
    )


def pipeline():
    return function_body(
        ALPHA_SOURCE,
        "void SceneShaderForwardMobile::ShaderData::_create_pipeline(",
        "void SceneShaderForwardMobile::ShaderData::",
    )


class MobileAlphaScissorTests(unittest.TestCase):
    """PR #125558: opaque alpha-scissor surfaces do not use alpha blend."""

    def setUp(self):
        self.text = source(ALPHA_SOURCE)
        self.region = self.text.split("RD::PipelineColorBlendState blend_state;", 1)[1].split(
            "\n\t} else {", 1
        )[0]

    def test_pipeline_creation_still_declares_blend_state(self):
        self.assertIn("RD::PipelineColorBlendState blend_state;", self.text)

    def test_alpha_pass_is_required_to_blend(self):
        self.assertIn("if ((uses_alpha || uses_blend_alpha) && uses_alpha_pass()) {", self.region)

    def test_uses_alpha_case_preserved(self):
        self.assertIn("uses_alpha || uses_blend_alpha", self.region)

    def test_explicit_blend_alpha_case_preserved(self):
        self.assertIn("uses_blend_alpha", self.region)

    def test_old_unconditional_alpha_check_removed(self):
        self.assertNotIn("if (uses_alpha || uses_blend_alpha) {", self.text)

    def test_alpha_to_coverage_preserved(self):
        self.assertIn("ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE", self.region)

    def test_alpha_to_one_preserved(self):
        self.assertIn("ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE_AND_TO_ONE", self.region)

    def test_blend_state_still_assigned_for_alpha_pass(self):
        self.assertIn("blend_state = blend_state_blend;", self.region)


class InstanceUniformAllocationTests(unittest.TestCase):
    """PR #125553: reused uniform blocks never retain previous shader values."""

    def test_gles_initializes_uniform_bytes(self):
        self.assertIn("memset(&global_shader_uniforms.buffer_values[pos], 0", allocate(GLES_SOURCE))

    def test_rd_initializes_uniform_bytes(self):
        self.assertIn("memset(&global_shader_uniforms.buffer_values[pos], 0", allocate(RD_SOURCE))

    def test_gles_initializes_entire_slot(self):
        self.assertIn("sizeof(GlobalShaderUniforms::Value) * ShaderLanguage::MAX_INSTANCE_UNIFORM_INDICES",
                      allocate(GLES_SOURCE))

    def test_rd_initializes_entire_slot(self):
        self.assertIn("sizeof(GlobalShaderUniforms::Value) * ShaderLanguage::MAX_INSTANCE_UNIFORM_INDICES",
                      allocate(RD_SOURCE))

    def test_gles_notifies_buffer_upload(self):
        self.assertIn("_global_shader_uniform_mark_buffer_dirty(pos, ShaderLanguage::MAX_INSTANCE_UNIFORM_INDICES)",
                      allocate(GLES_SOURCE))

    def test_rd_notifies_buffer_upload(self):
        self.assertIn("_global_shader_uniform_mark_buffer_dirty(pos, ShaderLanguage::MAX_INSTANCE_UNIFORM_INDICES)",
                      allocate(RD_SOURCE))

    def test_gles_checks_allocation_before_writing(self):
        text = allocate(GLES_SOURCE)
        self.assertLess(text.index("ERR_FAIL_COND_V_MSG(pos < 0"),
                        text.index("memset(&global_shader_uniforms.buffer_values[pos]"))

    def test_rd_checks_allocation_before_writing(self):
        text = allocate(RD_SOURCE)
        self.assertLess(text.index("ERR_FAIL_COND_V_MSG(pos < 0"),
                        text.index("memset(&global_shader_uniforms.buffer_values[pos]"))

    def test_gles_usage_recorded_before_zeroing(self):
        text = allocate(GLES_SOURCE)
        self.assertLess(text.index("global_shader_uniforms.buffer_usage[pos].elements ="),
                        text.index("memset(&global_shader_uniforms.buffer_values[pos]"))

    def test_rd_usage_recorded_before_zeroing(self):
        text = allocate(RD_SOURCE)
        self.assertLess(text.index("global_shader_uniforms.buffer_usage[pos].elements ="),
                        text.index("memset(&global_shader_uniforms.buffer_values[pos]"))

    def test_gles_marks_dirty_after_reset(self):
        text = allocate(GLES_SOURCE)
        self.assertLess(text.index("memset(&global_shader_uniforms.buffer_values[pos]"),
                        text.index("_global_shader_uniform_mark_buffer_dirty(pos, ShaderLanguage::MAX_INSTANCE_UNIFORM_INDICES)"))

    def test_rd_marks_dirty_after_reset(self):
        text = allocate(RD_SOURCE)
        self.assertLess(text.index("memset(&global_shader_uniforms.buffer_values[pos]"),
                        text.index("_global_shader_uniform_mark_buffer_dirty(pos, ShaderLanguage::MAX_INSTANCE_UNIFORM_INDICES)"))

    def test_gles_retains_duplicate_instance_guard(self):
        self.assertIn("global_shader_uniforms.instance_buffer_pos.has(p_instance)", allocate(GLES_SOURCE))

    def test_rd_retains_duplicate_instance_guard(self):
        self.assertIn("global_shader_uniforms.instance_buffer_pos.has(p_instance)", allocate(RD_SOURCE))


class SteamVRVulkanExtensionTests(unittest.TestCase):
    """PR #125552: enable optional extension for SteamVR interoperability."""

    def setUp(self):
        self.text = source(VULKAN_SOURCE)
        self.region = self.text.split("Error RenderingDeviceDriverVulkan::_initialize_device_extensions()", 1)[1].split(
            "uint32_t device_extension_count", 1
        )[0]

    def test_extension_name_present(self):
        self.assertIn("VK_EXT_SHADER_VIEWPORT_INDEX_LAYER_EXTENSION_NAME", self.region)

    def test_extension_requested_as_optional(self):
        self.assertIn("_register_requested_device_extension(VK_EXT_SHADER_VIEWPORT_INDEX_LAYER_EXTENSION_NAME, false);",
                      self.region)

    def test_extension_only_registered_once(self):
        self.assertEqual(self.region.count("VK_EXT_SHADER_VIEWPORT_INDEX_LAYER_EXTENSION_NAME"), 1)

    def test_external_memory_extension_preserved(self):
        self.assertIn("_register_requested_device_extension(VK_KHR_EXTERNAL_MEMORY_FD_EXTENSION_NAME, false);",
                      self.region)

    def test_steamvr_extension_after_external_memory(self):
        self.assertLess(self.region.index("VK_KHR_EXTERNAL_MEMORY_FD_EXTENSION_NAME"),
                        self.region.index("VK_EXT_SHADER_VIEWPORT_INDEX_LAYER_EXTENSION_NAME"))

    def test_non_semantic_info_registration_preserved(self):
        self.assertIn("VK_KHR_SHADER_NON_SEMANTIC_INFO_EXTENSION_NAME", self.region)

    def test_extension_before_enumeration(self):
        self.assertLess(self.text.index("VK_EXT_SHADER_VIEWPORT_INDEX_LAYER_EXTENSION_NAME"),
                        self.text.index("vkEnumerateDeviceExtensionProperties("))

    def test_other_vulkan_extensions_remain_optional(self):
        self.assertIn("_register_requested_device_extension(VK_KHR_SYNCHRONIZATION_2_EXTENSION_NAME, false);",
                      self.region)


if __name__ == "__main__":
    unittest.main()
