"""Regression contracts for upstream Godot #125620 and #125621.

Source-level lifecycle checks: they do not replace building the engine or
a real display-initialization failure integration test.
"""

from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def read_source(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


def function_body(source: str, signature: str) -> str:
    start = source.index(signature)
    first = source.index("{", start)
    level = 0
    for index in range(first, len(source)):
        if source[index] == "{":
            level += 1
        elif source[index] == "}":
            level -= 1
            if level == 0:
                return source[first + 1 : index]
    raise AssertionError(f"Could not find function end: {signature}")


class GDScriptModuleShutdownTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        src = read_source("modules/gdscript/register_types.cpp")
        cls.initialize = function_body(src, "void initialize_gdscript_module(")
        cls.shutdown = function_body(src, "void uninitialize_gdscript_module(")
        cls.shutdown_tools = cls.shutdown.split("#ifdef TOOLS_ENABLED", 1)[1]

    def test_registration_occurs_at_server_initialization_level(self):
        self.assertRegex(
            self.initialize,
            r"if \(p_level == MODULE_INITIALIZATION_LEVEL_SERVERS\)\s*\{[^}]*"
            r"gdscript_translation_parser_plugin\.instantiate\(\);[^}]*"
            r"EditorTranslationParser::get_singleton\(\)->add_parser\(",
        )

    def test_parser_is_removed_at_server_shutdown_level(self):
        self.assertRegex(
            self.shutdown_tools,
            r"if \(p_level == MODULE_INITIALIZATION_LEVEL_SERVERS\)\s*\{\s*"
            r"EditorTranslationParser::get_singleton\(\)->remove_parser\(",
        )

    def test_parser_removed_before_reference_released(self):
        self.assertRegex(
            self.shutdown_tools,
            r"remove_parser\(gdscript_translation_parser_plugin, EditorTranslationParser::STANDARD\);\s*"
            r"gdscript_translation_parser_plugin\.unref\(\);",
        )

    def test_editor_shutdown_frees_language_objects_without_parser(self):
        editor = self.shutdown_tools.split("} else if (p_level == MODULE_INITIALIZATION_LEVEL_EDITOR) {", 1)[1]
        self.assertNotIn("remove_parser", editor)
        self.assertNotIn("gdscript_translation_parser_plugin.unref()", editor)
        self.assertIn("memdelete(GDScriptEditorLanguage::get_singleton());", editor)

    def test_parser_cleanup_happens_exactly_once(self):
        self.assertEqual(self.shutdown.count("->remove_parser(gdscript_translation_parser_plugin"), 1)
        self.assertEqual(self.shutdown.count("gdscript_translation_parser_plugin.unref();"), 1)

    def test_lsp_cleanup_remains_editor_scoped(self):
        editor = self.shutdown_tools.split("} else if (p_level == MODULE_INITIALIZATION_LEVEL_EDITOR) {", 1)[1]
        self.assertIn("memdelete(GDScriptLanguageProtocol::get_singleton());", editor)
        server = self.shutdown_tools.split("} else if (p_level == MODULE_INITIALIZATION_LEVEL_EDITOR) {", 1)[0]
        self.assertNotIn("memdelete(GDScriptLanguageProtocol", server)


class DisplayFailureCleanupTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        src = read_source("main/main.cpp")
        cls.finalize = function_body(src, "void finalize_display()")
        marker = src.index('ERR_PRINT("Unable to create DisplayServer, all display drivers failed.')
        failure_start = src.rfind("if (err != OK || display_server == nullptr) {", 0, marker)
        if failure_start < 0:
            raise AssertionError("Could not locate final DisplayServer failure branch")
        cls.failure = function_body(src[failure_start:], "if (err != OK || display_server == nullptr)")

    def test_rendering_server_finishes_before_deletion(self):
        self.assertLess(self.finalize.index("rendering_server->finish();"), self.finalize.index("memdelete(rendering_server);"))

    def test_display_finalizer_releases_accessibility_server(self):
        self.assertIn("memdelete(accessibility_server);", self.finalize)
        self.assertIn("accessibility_server = nullptr;", self.finalize)

    def test_failure_uses_shared_display_finalizer(self):
        self.assertIn("finalize_display();", self.failure)
        self.assertNotIn("memdelete(display_server);", self.failure)

    def test_failure_finalizes_both_navigation_managers(self):
        self.assertIn("NavigationServer2DManager::finalize_server_manager();", self.failure)
        self.assertIn("NavigationServer3DManager::finalize_server_manager();", self.failure)

    def test_navigation_cleanup_respects_feature_flags(self):
        self.assertRegex(self.failure, r"#ifndef NAVIGATION_2D_DISABLED\s*NavigationServer2DManager::finalize_server_manager\(\);\s*#endif")
        self.assertRegex(self.failure, r"#ifndef NAVIGATION_3D_DISABLED\s*NavigationServer3DManager::finalize_server_manager\(\);\s*#endif")

    def test_display_and_navigation_finalize_before_module_unload(self):
        display = self.failure.index("finalize_display();")
        nav2d = self.failure.index("NavigationServer2DManager::finalize_server_manager();")
        nav3d = self.failure.index("NavigationServer3DManager::finalize_server_manager();")
        unload = self.failure.index("uninitialize_modules(MODULE_INITIALIZATION_LEVEL_SERVERS);")
        self.assertLess(display, nav2d)
        self.assertLess(nav2d, unload)
        self.assertLess(nav3d, unload)

    def test_error_path_keeps_physics_server_cleanup(self):
        self.assertIn("PhysicsServer2DManager::finalize_server_manager();", self.failure)
        self.assertIn("PhysicsServer3DManager::finalize_server_manager();", self.failure)

    def test_error_path_returns_original_failure(self):
        self.assertRegex(self.failure, r"return err;\s*$")


if __name__ == "__main__":
    unittest.main()
