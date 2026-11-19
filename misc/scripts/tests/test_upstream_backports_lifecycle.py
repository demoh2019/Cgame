#!/usr/bin/env python3
"""Fast source-level safeguards for upstream fixes ported to Cgame.

These contracts verify integration placement and run without Godot/Vulkan.
Native C++ tests and GPU runtime validation remain separate requirements.
"""

from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def source(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def function_body(code: str, signature: str) -> str:
    start = code.index(signature)
    brace = code.index("{", start)
    depth = 0
    for i in range(brace, len(code)):
        if code[i] == "{":
            depth += 1
        elif code[i] == "}":
            depth -= 1
            if depth == 0:
                return code[brace + 1:i]
    raise AssertionError("Unbalanced function: " + signature)


class GDScriptModuleLifecycleContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        code = source("modules/gdscript/register_types.cpp")
        cls.initialize = function_body(code, "void initialize_gdscript_module(")
        cls.uninitialize = function_body(code, "void uninitialize_gdscript_module(")

    def test_registration_occurs_at_servers_level(self):
        block = self.initialize
        start = block.index("#ifdef TOOLS_ENABLED")
        self.assertIn("if (p_level == MODULE_INITIALIZATION_LEVEL_SERVERS)", block[start:])
        self.assertLess(block.index("MODULE_INITIALIZATION_LEVEL_SERVERS", start),
                        block.index("->add_parser(", start))

    def test_removal_occurs_at_same_servers_level(self):
        block = self.uninitialize
        start = block.index("#ifdef TOOLS_ENABLED")
        self.assertRegex(block[start:], r"if \(p_level == MODULE_INITIALIZATION_LEVEL_SERVERS\)"
                         r"\s*\{\s*EditorTranslationParser::get_singleton\(\)->remove_parser")

    def test_parser_ref_is_released_after_unregistering(self):
        block = self.uninitialize
        self.assertLess(block.index("->remove_parser("),
                        block.index("gdscript_translation_parser_plugin.unref();"))

    def test_language_server_teardown_stays_at_editor_level(self):
        block = self.uninitialize
        self.assertRegex(block, r"else if \(p_level == MODULE_INITIALIZATION_LEVEL_EDITOR\)"
                         r"\s*\{\s*#ifndef GDSCRIPT_NO_LSP")
        self.assertLess(block.index("MODULE_INITIALIZATION_LEVEL_EDITOR"),
                        block.index("memdelete(GDScriptLanguageProtocol::get_singleton())"))
        self.assertLess(block.index("MODULE_INITIALIZATION_LEVEL_EDITOR"),
                        block.index("memdelete(GDScriptEditorLanguage::get_singleton())"))


class StringNameLifecycleContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        code = source("core/string/string_name.cpp")
        cls.cstring = function_body(code, "StringName::StringName(const char *p_name, bool p_static)")
        cls.string = function_body(code, "StringName::StringName(const String &p_name, bool p_static)")

    def test_null_and_empty_c_strings_skip_table_check(self):
        self.assertLess(self.cstring.index("if (!p_name || p_name[0] == 0)"),
                        self.cstring.index("ERR_FAIL_COND(!Table::configured)"))

    def test_empty_string_skips_table_check(self):
        self.assertLess(self.string.index("if (p_name.is_empty())"),
                        self.string.index("ERR_FAIL_COND(!Table::configured)"))

    def test_nonempty_c_strings_are_still_guarded(self):
        self.assertLess(self.cstring.index("ERR_FAIL_COND(!Table::configured)"),
                        self.cstring.index("const uint32_t hash = String::hash(p_name)"))

    def test_nonempty_strings_are_still_guarded(self):
        self.assertLess(self.string.index("ERR_FAIL_COND(!Table::configured)"),
                        self.string.index("const uint32_t hash = p_name.hash()"))

    def test_native_static_initialization_regression_is_registered(self):
        native = source("tests/core/string/test_string_name.cpp")
        self.assertIn("TEST_FORCE_LINK(test_string_name)", native)
        self.assertIn('static StringName early_empty_c_string("");', native)
        self.assertIn("static StringName early_null_c_string(nullptr);", native)
        self.assertGreaterEqual(native.count("CHECK(") + native.count("CHECK_FALSE("), 25)


class VulkanPipelineCacheContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.serialize = function_body(
            source("drivers/vulkan/rendering_device_driver_vulkan.cpp"),
            "Vector<uint8_t> RenderingDeviceDriverVulkan::pipeline_cache_serialize()",
        )

    def test_cache_buffer_is_trimmed_after_driver_data_query(self):
        block = self.serialize
        query = block.index("vkGetPipelineCacheData(")
        trim = block.rindex("pipelines_cache.buffer.resize(")
        header = block.index("PipelineCacheHeader *header")
        self.assertLess(query, trim)
        self.assertLess(trim, header)

    def test_final_cache_length_includes_exact_payload_and_header(self):
        block = self.serialize
        self.assertEqual(
            block.count("pipelines_cache.buffer.resize("
                        "pipelines_cache.current_size + sizeof(PipelineCacheHeader))"),
            2,
        )

    def test_cache_header_and_hash_use_returned_payload_size(self):
        block = self.serialize
        self.assertIn("header->data_size = pipelines_cache.current_size;", block)
        self.assertIn("pipelines_cache.current_size);", block)
        self.assertLess(block.rindex("pipelines_cache.buffer.resize("),
                        block.index("header->data_hash ="))


if __name__ == "__main__":
    unittest.main()
