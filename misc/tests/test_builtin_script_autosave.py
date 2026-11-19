#!/usr/bin/env python3
"""Regression contracts for Godot #125180 built-in script auto-formatting.

These source-level tests guard the editor save-flow wiring. They are NOT a
substitute for a compiled editor or an interactive scene-save integration test.
"""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[2]
EDITOR_CPP = ROOT / "editor" / "editor_node.cpp"
SCRIPT_CPP = ROOT / "editor" / "script" / "script_editor_plugin.cpp"
SCRIPT_H = ROOT / "editor" / "script" / "script_editor_plugin.h"


def function_body(source: str, signature: str) -> str:
    """Find one C++ definition and return its brace-balanced body."""
    matches = list(re.finditer(re.escape(signature) + r"\s*\{", source))
    if len(matches) != 1:
        raise AssertionError(f"Expected one definition of {signature}, got {len(matches)}")
    i = matches[0].end() - 1
    depth = 0
    for j in range(i, len(source)):
        if source[j] == "{":
            depth += 1
        elif source[j] == "}":
            depth -= 1
            if depth == 0:
                return source[i + 1:j]
    raise AssertionError(f"Unclosed function: {signature}")


class TestBuiltinScriptAutosave(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.editor = EDITOR_CPP.read_text(encoding="utf-8")
        cls.script = SCRIPT_CPP.read_text(encoding="utf-8")
        cls.header = SCRIPT_H.read_text(encoding="utf-8")
        cls.save_scene = function_body(cls.editor, "void EditorNode::_save_scene(String p_file, int idx)")
        cls.format_all = function_body(
            cls.script, "void DocumentEditorContainer::auto_format_all_scripts()"
        )
        cls.format_text = function_body(
            cls.script, "void DocumentEditorContainer::_auto_format_text(ScriptEditorBase *p_seb)"
        )

    def test_scene_save_formats_scripts(self):
        self.assertIn("ScriptEditor::get_singleton()->auto_format_all_scripts();", self.save_scene)

    def test_format_runs_before_editor_changes_are_applied(self):
        self.assertLess(
            self.save_scene.index("auto_format_all_scripts()"),
            self.save_scene.index("editor_data.apply_changes_in_editors();"),
        )

    def test_format_runs_before_scene_is_packed(self):
        self.assertLess(
            self.save_scene.index("auto_format_all_scripts()"),
            self.save_scene.index("sdata->pack(scene)"),
        )

    def test_format_runs_only_after_pre_save_notification(self):
        self.assertLess(
            self.save_scene.index("NOTIFICATION_EDITOR_PRE_SAVE"),
            self.save_scene.index("auto_format_all_scripts()"),
        )

    def test_format_does_not_write_files_in_pre_save_step(self):
        before_apply = self.save_scene.split("editor_data.apply_changes_in_editors();")[0]
        self.assertNotIn("ResourceSaver::save(", before_apply)
        self.assertNotIn("FileAccess::open(", before_apply)

    def test_public_editor_facade_exists(self):
        self.assertIn(
            "void auto_format_all_scripts() { script_container->auto_format_all_scripts(); }",
            self.header,
        )

    def test_container_public_declaration_exists(self):
        self.assertEqual(self.header.count("void auto_format_all_scripts();"), 1)

    def test_single_container_implementation(self):
        self.assertEqual(
            self.script.count("void DocumentEditorContainer::auto_format_all_scripts()"),
            1,
        )

    def test_every_open_tab_is_visited(self):
        self.assertIn("for (int i = 0; i < tab_container->get_tab_count(); i++)", self.format_all)

    def test_uses_actual_tab_controls(self):
        self.assertIn("tab_container->get_tab_control(i)", self.format_all)

    def test_skips_tabs_that_are_not_script_editors(self):
        self.assertIn("Object::cast_to<ScriptEditorBase>", self.format_all)
        self.assertRegex(self.format_all, r"if\s*\(!seb\)\s*\{\s*continue;")

    def test_calls_existing_autofmt_per_editor(self):
        self.assertEqual(self.format_all.count("_auto_format_text(seb);"), 1)

    def test_no_direct_source_rewrite_or_forced_external_save(self):
        self.assertNotIn("set_source_code(", self.format_all)
        self.assertNotIn("ResourceSaver::save(", self.format_all)
        self.assertNotIn("save_resource(", self.format_all)

    def test_respects_trim_whitespace_user_option(self):
        self.assertIn("if (trim_trailing_whitespace_on_save)", self.format_text)
        self.assertIn("teb->trim_trailing_whitespace();", self.format_text)

    def test_respects_trim_final_newlines_user_option(self):
        self.assertIn("if (trim_final_newlines_on_save)", self.format_text)
        self.assertIn("teb->trim_final_newlines();", self.format_text)

    def test_respects_indent_conversion_user_option(self):
        self.assertIn("if (convert_indent_on_save)", self.format_text)
        self.assertIn("teb->convert_indent();", self.format_text)

    def test_existing_save_current_script_path_still_formats(self):
        body = function_body(
            self.script, "void DocumentEditorContainer::save_current_script()"
        )
        self.assertIn("_auto_format_text(current);", body)

    def test_existing_save_all_scripts_path_still_formats(self):
        body = function_body(
            self.script, "void DocumentEditorContainer::save_all_scripts()"
        )
        self.assertIn("_auto_format_text(seb);", body)

    def test_scene_pack_still_has_error_handling(self):
        self.assertIn("Error err = sdata->pack(scene);", self.save_scene)
        self.assertIn("if (err != OK)", self.save_scene)


if __name__ == "__main__":
    unittest.main()
