"""Upstream #125554 GDScript static variable debugger integration contracts.

Fast, inspectable source regression checks. Run native Godot + debugger
integration tests before declaring the feature production-validated.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class CoreDebuggerTests(unittest.TestCase):
    def test_script_language_declares_static_debug_hook(self):
        self.assertIn("virtual void debug_get_static_variables(List<String> *r_names, List<Variant> *r_values)",
                      read("core/object/script_language.h"))

    def test_local_debugger_command_alias(self):
        self.assertIn('line == "sv" || line == "static vars"',
                      read("core/debugger/local_debugger.cpp"))

    def test_local_debugger_retrieves_static_values(self):
        self.assertIn("script_lang->debug_get_static_variables(&static_vars, &values);",
                      read("core/debugger/local_debugger.cpp"))

    def test_local_debugger_prints_static_values(self):
        self.assertIn("print_variables(static_vars, values, variable_prefix);",
                      read("core/debugger/local_debugger.cpp"))

    def test_local_debugger_help_mentions_command(self):
        self.assertIn("sv,static vars", read("core/debugger/local_debugger.cpp"))

    def test_remote_debugger_retrieves_static_values(self):
        self.assertIn("debug_get_static_variables(&static_names, &static_vals)",
                      read("core/debugger/remote_debugger.cpp"))

    def test_remote_debugger_checks_names_value_count(self):
        self.assertIn("ERR_FAIL_COND(static_names.size() != static_vals.size());",
                      read("core/debugger/remote_debugger.cpp"))

    def test_remote_debugger_includes_static_in_total(self):
        self.assertIn("globals_vals.size() + static_vals.size()",
                      read("core/debugger/remote_debugger.cpp"))

    def test_remote_debugger_static_scope_type_four(self):
        self.assertIn("_send_stack_vars(static_names, static_vals, 4);",
                      read("core/debugger/remote_debugger.cpp"))


class BacktraceAPITests(unittest.TestCase):
    def test_backtrace_stores_static_variables(self):
        self.assertIn("LocalVector<StackVariable> static_variables;",
                      read("core/object/script_backtrace.h"))

    def test_backtrace_exposes_count(self):
        self.assertIn("get_static_variable_count() const",
                      read("core/object/script_backtrace.h"))

    def test_backtrace_exposes_name(self):
        self.assertIn("get_static_variable_name(int p_variable_index)",
                      read("core/object/script_backtrace.h"))

    def test_backtrace_exposes_value(self):
        self.assertIn("get_static_variable_value(int p_variable_index)",
                      read("core/object/script_backtrace.h"))

    def test_backtrace_fetches_script_static_values(self):
        self.assertIn("p_language->debug_get_static_variables(&statics_names, &statics_values)",
                      read("core/object/script_backtrace.cpp"))

    def test_backtrace_stores_paired_variables(self):
        self.assertIn("_store_variables(statics_names, statics_values, static_variables)",
                      read("core/object/script_backtrace.cpp"))

    def test_backtrace_getters_are_range_checked(self):
        self.assertGreaterEqual(read("core/object/script_backtrace.cpp").count(
            "ERR_FAIL_INDEX_V(p_variable_index, (int)static_variables.size()"), 2)

    def test_backtrace_binds_all_methods(self):
        src = read("core/object/script_backtrace.cpp")
        for name in ("get_static_variable_count", "get_static_variable_name",
                     "get_static_variable_value"):
            with self.subTest(method=name):
                self.assertIn('D_METHOD("' + name + '"', src)

    def test_backtrace_class_docs_describe_static_values(self):
        xml = read("doc/classes/ScriptBacktrace.xml")
        for name in ("get_static_variable_count", "get_static_variable_name",
                     "get_static_variable_value"):
            with self.subTest(method=name):
                self.assertIn('<method name="' + name + '"', xml)


class ExtensionIntegrationTests(unittest.TestCase):
    def test_virtual_extension_hook_registered(self):
        self.assertIn("GDVIRTUAL_BIND(_debug_get_static_variables)",
                      read("core/object/script_language_extension.cpp"))

    def test_extension_header_declares_hook(self):
        self.assertIn("GDVIRTUAL0R(Dictionary, _debug_get_static_variables)",
                      read("core/object/script_language_extension.h"))

    def test_extension_converts_name_list(self):
        self.assertIn('ret.has("static_names")',
                      read("core/object/script_language_extension.h"))

    def test_extension_converts_variant_values(self):
        self.assertIn('ret.has("values")',
                      read("core/object/script_language_extension.h"))

    def test_extension_can_omit_static_variables(self):
        self.assertIn("if (ret.is_empty())",
                      read("core/object/script_language_extension.h"))

    def test_extension_documentation_exists(self):
        self.assertIn('<method name="_debug_get_static_variables"',
                      read("doc/classes/ScriptLanguageExtension.xml"))


class EditorDebuggerIntegrationTests(unittest.TestCase):
    def test_dap_has_five_scopes(self):
        self.assertIn("for (int j = 0; j < 5; j++)",
                      read("editor/debugger/debug_adapter/debug_adapter_protocol.cpp"))

    def test_dap_validates_five_scope_ids(self):
        self.assertIn("ERR_FAIL_COND(scope_ids.size() != 5)",
                      read("editor/debugger/debug_adapter/debug_adapter_protocol.cpp"))

    def test_dap_accepts_scope_type_four(self):
        self.assertIn("ERR_FAIL_INDEX(stack_var.type, 5)",
                      read("editor/debugger/debug_adapter/debug_adapter_protocol.cpp"))

    def test_inspector_labels_static_variables(self):
        self.assertIn('type = "Static Members/";',
                      read("editor/debugger/editor_debugger_inspector.cpp"))

    def test_script_tooltip_uses_qualified_static_name(self):
        src = read("editor/script/script_text_editor.cpp")
        self.assertIn('static_prefix + "/" + result_symbol', src)

    def test_script_tooltip_encodes_qualified_path(self):
        self.assertIn('result_symbol.uri_encode().replace(".", "%2E")',
                      read("editor/script/script_text_editor.cpp"))

    def test_script_tooltip_avoids_dereferencing_missing_script(self):
        src = read("editor/script/script_text_editor.cpp")
        start = src.index("const Ref<Script> result_script = ResourceLoader::load(result.script_path)")
        end = src.index("const String script_global_name = result_script->get_global_name()", start)
        self.assertIn("if (result_script.is_valid())", src[start:end])

    def test_script_tooltip_passes_qualified_value_to_debugger(self):
        self.assertIn("EditorDebuggerNode::get_singleton()->get_var_value(result_symbol)",
                      read("editor/script/script_text_editor.cpp"))


class GDScriptStaticValuesTests(unittest.TestCase):
    def test_gdscript_declares_static_index_accessor(self):
        self.assertIn("debug_get_static_member_indices() const",
                      read("modules/gdscript/gdscript.h"))

    def test_gdscript_language_overrides_static_debug_hook(self):
        self.assertIn("virtual void debug_get_static_variables(List<String> *r_names, List<Variant> *r_values) override;",
                      read("modules/gdscript/gdscript.h"))

    def test_script_cache_lists_static_scripts(self):
        self.assertIn("static void get_static_scripts(List<Ref<GDScript>> *r_scripts);",
                      read("modules/gdscript/gdscript_cache.h"))

    def test_static_cache_traversal_reads_static_script_cache(self):
        self.assertIn("singleton->static_gdscript_cache",
                      read("modules/gdscript/gdscript_cache.cpp"))

    def test_language_collects_all_cached_static_scripts(self):
        self.assertIn("GDScriptCache::get_static_scripts(&static_scripts)",
                      read("modules/gdscript/gdscript_editor.cpp"))

    def test_language_uses_static_member_indices(self):
        self.assertIn("debug_get_static_member_indices()",
                      read("modules/gdscript/gdscript_editor.cpp"))

    def test_language_qualifies_static_names(self):
        self.assertIn('vformat("%s/%s", script_name, E.key)',
                      read("modules/gdscript/gdscript_editor.cpp"))

    def test_language_fetches_live_static_values(self):
        self.assertIn("r_values->push_back(script->get(E.key))",
                      read("modules/gdscript/gdscript_editor.cpp"))

    def test_language_has_autoload_and_script_name_fallbacks(self):
        src = read("modules/gdscript/gdscript_editor.cpp")
        self.assertIn("autoload_names.has(script)", src)
        self.assertIn("script->get_global_name()", src)
        self.assertIn("script->get_path()", src)


if __name__ == "__main__":
    unittest.main()
