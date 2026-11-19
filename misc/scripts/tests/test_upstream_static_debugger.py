#!/usr/bin/env python3
"""Integration contracts for upstream #125554 static-variable debugging.

These source-level guards cover protocol scope IDs, serialization, defensive
script lookup, API exposure, and XML metadata. They complement (rather than
replace) a native Godot editor/debugger build.
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path
from xml.etree import ElementTree

ROOT = Path(__file__).resolve().parents[3]


def source(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


class StaticDebuggerContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.local = source("core/debugger/local_debugger.cpp")
        cls.remote = source("core/debugger/remote_debugger.cpp")
        cls.backtrace = source("core/object/script_backtrace.cpp")
        cls.backtrace_header = source("core/object/script_backtrace.h")
        cls.language_header = source("core/object/script_language.h")
        cls.extension = source("core/object/script_language_extension.cpp")
        cls.extension_header = source("core/object/script_language_extension.h")
        cls.protocol = source("editor/debugger/debug_adapter/debug_adapter_protocol.cpp")
        cls.inspector = source("editor/debugger/editor_debugger_inspector.cpp")
        cls.text_editor = source("editor/script/script_text_editor.cpp")
        cls.gdscript = source("modules/gdscript/gdscript.h")
        cls.gdscript_editor = source("modules/gdscript/gdscript_editor.cpp")
        cls.cache = source("modules/gdscript/gdscript_cache.cpp")
        cls.cache_header = source("modules/gdscript/gdscript_cache.h")

    def test_local_debugger_lists_static_variables(self):
        self.assertIn('line == "sv" || line == "static vars"', self.local)
        self.assertIn("script_lang->debug_get_static_variables(&static_vars, &values);", self.local)
        self.assertIn("print_variables(static_vars, values, variable_prefix);", self.local)

    def test_local_debugger_describes_static_command(self):
        self.assertIn("sv,static vars", self.local)

    def test_remote_debugger_includes_statics_in_payload_length(self):
        self.assertIn("globals_vals.size() + static_vals.size()", self.remote)
        self.assertIn("ERR_FAIL_COND(static_names.size() != static_vals.size());", self.remote)

    def test_remote_debugger_encodes_statics_as_scope_four(self):
        self.assertIn("_send_stack_vars(static_names, static_vals, 4);", self.remote)

    def test_debug_adapter_allocates_five_scopes(self):
        self.assertIn("for (int j = 0; j < 5; j++)", self.protocol)
        self.assertIn("ERR_FAIL_COND(scope_ids.size() != 5);", self.protocol)
        self.assertIn("ERR_FAIL_INDEX(stack_var.type, 5);", self.protocol)

    def test_inspector_names_static_scope(self):
        self.assertRegex(self.inspector, r'case 4:\s*type = "Static Members/";')

    def test_script_backtrace_captures_statics(self):
        self.assertIn("LocalVector<StackVariable> static_variables;", self.backtrace_header)
        self.assertIn("p_language->debug_get_static_variables(&statics_names, &statics_values);", self.backtrace)
        self.assertIn("_store_variables(statics_names, statics_values, static_variables);", self.backtrace)

    def test_script_backtrace_indices_are_validated(self):
        self.assertGreaterEqual(self.backtrace.count("ERR_FAIL_INDEX_V(p_variable_index, (int)static_variables.size()"), 2)

    def test_script_backtrace_registers_public_accessors(self):
        for name in ("get_static_variable_count", "get_static_variable_name", "get_static_variable_value"):
            with self.subTest(method=name):
                self.assertIn('D_METHOD("' + name + '"', self.backtrace)
                self.assertIn(name, self.backtrace_header)

    def test_generic_language_has_default_safe_hook(self):
        self.assertIn("virtual void debug_get_static_variables(List<String> *r_names, List<Variant> *r_values) {}", self.language_header)

    def test_language_extension_exposes_debug_statics(self):
        self.assertIn("GDVIRTUAL_BIND(_debug_get_static_variables);", self.extension)
        self.assertIn("GDVIRTUAL0R(Dictionary, _debug_get_static_variables)", self.extension_header)
        self.assertIn('ret.has("static_names")', self.extension_header)
        self.assertIn('ret.has("values")', self.extension_header)

    def test_gdscript_implements_static_hook(self):
        self.assertIn("virtual void debug_get_static_variables(List<String> *r_names, List<Variant> *r_values) override;", self.gdscript)
        self.assertIn("void GDScriptLanguage::debug_get_static_variables(", self.gdscript_editor)

    def test_gdscript_uses_static_script_cache(self):
        self.assertIn("static void get_static_scripts(List<Ref<GDScript>> *r_scripts);", self.cache_header)
        self.assertIn("GDScriptCache::get_static_scripts(", self.cache)
        self.assertIn("GDScriptCache::get_static_scripts(&static_scripts);", self.gdscript_editor)

    def test_static_names_use_autoload_class_or_script_path(self):
        for snippet in ("autoload_names.has(script)", "script->get_global_name();", "script->get_path();",
                        'vformat("%s/%s", script_name, E.key)'):
            with self.subTest(snippet=snippet):
                self.assertIn(snippet, self.gdscript_editor)

    def test_static_tooltip_does_not_dereference_missing_script(self):
        # Regression beyond upstream patch: missing scripts can happen while
        # renaming or deleting files; check validity before get_global_name.
        start = self.text_editor.index("const Ref<Script> result_script = ResourceLoader::load(result.script_path);")
        tail = self.text_editor[start:start + 900]
        self.assertLess(tail.index("if (result_script.is_valid())"), tail.index("result_script->get_global_name()"))

    def test_tooltip_preserves_scoped_static_variable_lookup(self):
        self.assertIn('result_symbol = static_prefix + "/" + result_symbol;', self.text_editor)
        self.assertIn('result_symbol.uri_encode().replace(".", "%2E");', self.text_editor)
        self.assertIn("get_var_value(result_symbol)", self.text_editor)

    def test_backtrace_docs_have_matching_methods(self):
        root = ElementTree.fromstring(source("doc/classes/ScriptBacktrace.xml"))
        for name in ("get_static_variable_count", "get_static_variable_name", "get_static_variable_value"):
            with self.subTest(name=name):
                self.assertIsNotNone(root.find("./methods/method[@name='" + name + "']"))

    def test_language_extension_docs_include_virtual_method(self):
        root = ElementTree.fromstring(source("doc/classes/ScriptLanguageExtension.xml"))
        self.assertIsNotNone(root.find("./methods/method[@name='_debug_get_static_variables']"))


if __name__ == "__main__":
    unittest.main()
