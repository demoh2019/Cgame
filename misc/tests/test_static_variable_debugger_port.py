#!/usr/bin/env python3
"""Cross-layer source contracts for the port of Godot #125554.

This complements (does not replace) native doctests and full editor builds.
"""

from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


def source(path):
    return (ROOT / path).read_text(encoding="utf-8")


class TestStaticVariableDebuggerPort(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.bt_h = source("core/object/script_backtrace.h")
        cls.bt_cpp = source("core/object/script_backtrace.cpp")
        cls.lang_h = source("core/object/script_language.h")
        cls.ext_h = source("core/object/script_language_extension.h")
        cls.ext_cpp = source("core/object/script_language_extension.cpp")
        cls.local = source("core/debugger/local_debugger.cpp")
        cls.remote = source("core/debugger/remote_debugger.cpp")
        cls.protocol = source("editor/debugger/debug_adapter/debug_adapter_protocol.cpp")
        cls.inspector = source("editor/debugger/editor_debugger_inspector.cpp")
        cls.gd_h = source("modules/gdscript/gdscript.h")
        cls.gd_cache_h = source("modules/gdscript/gdscript_cache.h")
        cls.gd_cache_cpp = source("modules/gdscript/gdscript_cache.cpp")
        cls.gd_editor = source("modules/gdscript/gdscript_editor.cpp")
        cls.tooltip = source("editor/script/script_text_editor.cpp")

    def test_language_has_optional_static_api(self):
        self.assertIn("virtual void debug_get_static_variables(", self.lang_h)
        self.assertIn('r_values) {}', self.lang_h)

    def test_gdscript_override_exists(self):
        self.assertIn("debug_get_static_variables(List<String> *r_names, List<Variant> *r_values) override", self.gd_h)

    def test_cache_exposes_static_script_enumerator(self):
        self.assertIn("static void get_static_scripts(", self.gd_cache_h)
        self.assertIn("void GDScriptCache::get_static_scripts(", self.gd_cache_cpp)

    def test_cache_iteration_does_not_capture_raw_script_pointers(self):
        self.assertIn("r_scripts->push_back(KV.value);", self.gd_cache_cpp)
        self.assertIn("List<Ref<GDScript>>", self.gd_editor)

    def test_collector_accesses_existing_static_member_table(self):
        self.assertIn("debug_get_static_member_indices()", self.gd_editor)

    def test_collector_pairs_names_and_values(self):
        self.assertIn('r_names->push_back(full_name);', self.gd_editor)
        self.assertIn('r_values->push_back(script->get(E.key));', self.gd_editor)

    def test_collector_uses_qualified_static_names(self):
        self.assertIn('vformat("%s/%s", script_name, E.key)', self.gd_editor)

    def test_local_debugger_accepts_static_command(self):
        self.assertIn('line == "sv" || line == "static vars"', self.local)

    def test_local_debugger_queries_static_values(self):
        self.assertIn('script_lang->debug_get_static_variables(&static_vars, &values)', self.local)

    def test_remote_debugger_includes_static_variables_in_total(self):
        self.assertIn('globals_vals.size() + static_vals.size()', self.remote)

    def test_remote_debugger_sends_static_group_four(self):
        self.assertIn('_send_stack_vars(static_names, static_vals, 4);', self.remote)

    def test_debugger_inspector_has_static_members_group(self):
        self.assertIn('case 4:', self.inspector)
        self.assertIn('type = "Static Members/";', self.inspector)

    def test_dap_allocates_five_scope_identifiers(self):
        self.assertIn('for (int j = 0; j < 5; j++)', self.protocol)

    def test_dap_accepts_static_scope_index(self):
        self.assertIn('ERR_FAIL_INDEX(stack_var.type, 5);', self.protocol)
        self.assertIn('ERR_FAIL_COND(scope_ids.size() != 5);', self.protocol)

    def test_script_language_extension_exposes_virtual(self):
        self.assertIn('GDVIRTUAL0R(Dictionary, _debug_get_static_variables)', self.ext_h)
        self.assertIn('GDVIRTUAL_BIND(_debug_get_static_variables)', self.ext_cpp)

    def test_backtrace_has_static_variable_storage(self):
        self.assertIn('LocalVector<StackVariable> static_variables;', self.bt_h)

    def test_backtrace_exposes_public_static_accessors(self):
        for method in ['get_static_variable_count', 'get_static_variable_name', 'get_static_variable_value']:
            with self.subTest(method=method):
                self.assertIn(method, self.bt_h)
                self.assertIn('D_METHOD("' + method + '"', self.bt_cpp)

    def test_backtrace_captures_static_only_on_variable_request(self):
        match = re.search(
            r'if \(p_include_variables\) \{(?P<body>.*?)\n\t\}',
            self.bt_cpp, flags=re.DOTALL
        )
        self.assertIsNotNone(match)
        self.assertIn('p_language->debug_get_static_variables', match.group('body'))

    def test_backtrace_preserves_names_and_values(self):
        self.assertIn('_store_variables(statics_names, statics_values, static_variables);', self.bt_cpp)

    def test_tooltip_checks_valid_resource_before_use(self):
        block = self.tooltip.split('String static_prefix;', 1)[1].split('String result_symbol =', 1)[0]
        self.assertIn('!result.script_path.is_empty()', block)
        self.assertIn('if (result_script.is_valid())', block)
        self.assertGreater(block.index('get_global_name()'), block.index('if (result_script.is_valid())'))

    def test_tooltip_does_not_resolve_missing_paths(self):
        block = self.tooltip.split('String static_prefix;', 1)[1].split('String result_symbol =', 1)[0]
        self.assertIn('result.script_path.is_empty()', block)

    def test_static_api_documented(self):
        doc = source("doc/classes/ScriptBacktrace.xml")
        for method in ['get_static_variable_count', 'get_static_variable_name', 'get_static_variable_value']:
            with self.subTest(method=method):
                self.assertIn('<method name="' + method + '"', doc)

    def test_extension_api_documented(self):
        self.assertIn('<method name="_debug_get_static_variables"', source("doc/classes/ScriptLanguageExtension.xml"))

    def test_native_tests_registered(self):
        reg = source("modules/gdscript/register_types.cpp")
        suite = source("modules/gdscript/tests/test_static_variable_debugger.h")
        self.assertIn('tests/test_static_variable_debugger.h', reg)
        self.assertGreaterEqual(suite.count('TEST_CASE('), 5)


if __name__ == "__main__":
    unittest.main()
