"""Regression contracts for upstream #125620 and #125621 lifecycle fixes.

These fast source-level tests supplement, rather than replace, the compiled
editor startup/shutdown smoke job in upstream-lifecycle-backports.yml.
"""

from __future__ import annotations

from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
GDSCRIPT = ROOT / "modules/gdscript/register_types.cpp"
MAIN = ROOT / "main/main.cpp"


def _function(source: str, name: str, next_marker: str) -> str:
    start = source.index(name)
    end = source.find(next_marker, start + len(name))
    return source[start:end if end >= 0 else None]


def _failed_display_block(source: str) -> str:
    start = source.index('ERR_PRINT("Unable to create DisplayServer, all display drivers failed.')
    end = source.index("return err;", start)
    return source[start:end]


class GDScriptTranslationParserLifecycleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = GDSCRIPT.read_text(encoding="utf-8")
        cls.initialize = _function(cls.source, "void initialize_gdscript_module(", "void uninitialize_gdscript_module(")
        cls.uninitialize = _function(cls.source, "void uninitialize_gdscript_module(", "\n#ifdef TESTS_ENABLED")

    def test_registration_at_servers_level(self):
        self.assertRegex(self.initialize, r"if \(p_level == MODULE_INITIALIZATION_LEVEL_SERVERS\) \{\s*EditorNode::add_init_callback")
        self.assertEqual(self.initialize.count("add_parser(gdscript_translation_parser_plugin"), 1)

    def test_unregistration_at_servers_level(self):
        self.assertRegex(self.uninitialize, r"#ifdef TOOLS_ENABLED\s+if \(p_level == MODULE_INITIALIZATION_LEVEL_SERVERS\) \{\s*EditorTranslationParser::get_singleton\(\)->remove_parser\(")

    def test_removal_not_performed_at_editor_level(self):
        tools = self.uninitialize.split("#ifdef TOOLS_ENABLED", 1)[1]
        server, editor = tools.split("} else if (p_level == MODULE_INITIALIZATION_LEVEL_EDITOR) {", 1)
        self.assertIn("remove_parser(gdscript_translation_parser_plugin", server)
        self.assertNotIn("remove_parser(gdscript_translation_parser_plugin", editor)

    def test_parser_unref_at_servers_level(self):
        tools = self.uninitialize.split("#ifdef TOOLS_ENABLED", 1)[1]
        server, editor = tools.split("} else if (p_level == MODULE_INITIALIZATION_LEVEL_EDITOR) {", 1)
        self.assertEqual(server.count("gdscript_translation_parser_plugin.unref();"), 1)
        self.assertNotIn("gdscript_translation_parser_plugin.unref();", editor)

    def test_language_server_remains_editor_level(self):
        tools = self.uninitialize.split("#ifdef TOOLS_ENABLED", 1)[1]
        server, editor = tools.split("} else if (p_level == MODULE_INITIALIZATION_LEVEL_EDITOR) {", 1)
        self.assertNotIn("memdelete(GDScriptLanguageProtocol::get_singleton())", server)
        self.assertIn("memdelete(GDScriptLanguageProtocol::get_singleton())", editor)
        self.assertIn("memdelete(GDScriptEditorLanguage::get_singleton())", editor)

    def test_gdscript_engine_language_unregistration_unchanged(self):
        self.assertIn("ScriptServer::unregister_language(script_language_gd)", self.uninitialize)
        self.assertIn("GDScriptParser::cleanup();", self.uninitialize)
        self.assertIn("GDScriptUtilityFunctions::unregister_functions();", self.uninitialize)

    def test_tools_and_lsp_macro_guards_preserved(self):
        self.assertIn("#ifdef TOOLS_ENABLED", self.uninitialize)
        self.assertIn("#ifndef GDSCRIPT_NO_LSP", self.uninitialize)
        self.assertIn("#endif // TOOLS_ENABLED", self.uninitialize)


class DisplayServerFailureCleanupTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = MAIN.read_text(encoding="utf-8")
        cls.failure = _failed_display_block(cls.source)

    def test_failed_display_releases_all_display_resources(self):
        self.assertIn("finalize_display();", self.failure)
        self.assertNotIn("memdelete(display_server);", self.failure)
        self.assertNotIn("display_server = nullptr;", self.failure)

    def test_navigation_2d_manager_finalized_before_modules(self):
        self.assertIn("NavigationServer2DManager::finalize_server_manager();", self.failure)
        self.assertLess(self.failure.index("NavigationServer2DManager::finalize_server_manager();"),
                        self.failure.index("GDExtensionManager::get_singleton()->deinitialize_extensions("))

    def test_navigation_3d_manager_finalized_before_modules(self):
        self.assertIn("NavigationServer3DManager::finalize_server_manager();", self.failure)
        self.assertLess(self.failure.index("NavigationServer3DManager::finalize_server_manager();"),
                        self.failure.index("GDExtensionManager::get_singleton()->deinitialize_extensions("))

    def test_disabled_navigation_guards(self):
        for dim in ("2D", "3D"):
            with self.subTest(dim=dim):
                self.assertRegex(self.failure,
                                 rf"#ifndef NAVIGATION_{dim}_DISABLED\s+NavigationServer{dim}Manager::finalize_server_manager\(\);\s+#endif // NAVIGATION_{dim}_DISABLED")

    def test_display_cleanup_happens_before_extension_and_module_shutdown(self):
        self.assertLess(self.failure.index("finalize_display();"),
                        self.failure.index("GDExtensionManager::get_singleton()->deinitialize_extensions("))
        self.assertLess(self.failure.index("finalize_display();"),
                        self.failure.index("uninitialize_modules(MODULE_INITIALIZATION_LEVEL_SERVERS);"))

    def test_error_path_retains_server_and_input_cleanup(self):
        for snippet in ("unregister_server_types();", "memdelete(input);", "memdelete(tsman);",
                        "PhysicsServer2DManager::finalize_server_manager();",
                        "PhysicsServer3DManager::finalize_server_manager();"):
            with self.subTest(snippet=snippet):
                self.assertIn(snippet, self.failure)

    def test_normal_shutdown_still_finalizes_display(self):
        self.assertGreaterEqual(self.source.count("finalize_display();"), 2)
        self.assertRegex(self.source, r"void finalize_display\(\)\s*\{[^}]*")

    def test_failure_block_detector_targets_expected_path(self):
        self.assertIn("Use \\\"--headless\\\"", self.failure)
        self.assertNotIn("return OK;", self.failure)


if __name__ == "__main__":
    unittest.main()
