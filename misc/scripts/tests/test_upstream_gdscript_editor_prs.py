"""Source-level regression contracts for three adopted upstream editor PRs.

These tests check that critical branches and persisted keys survive refactors.
They do NOT replace compiling or exercising the editor itself.
"""

from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]


def source(path):
    return (ROOT / path).read_text(encoding="utf-8")


class GDScriptLookupContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        whole = source("modules/gdscript/gdscript_editor.cpp")
        cls.fn = whole.split("static bool _get_subscript_type(", 1)[1].split(
            "static void _find_call_arguments(", 1
        )[0]

    def test_script_type_is_detected(self):
        self.assertIn("r_base_type.kind = GDScriptParser::DataType::SCRIPT;", self.fn)

    def test_script_object_is_preserved(self):
        self.assertIn("r_base_type.script_type = scr;", self.fn)

    def test_script_path_is_propagated(self):
        self.assertIn("r_base_type.script_path = scr->get_path();", self.fn)

    def test_script_path_comes_after_script_identity(self):
        self.assertLess(self.fn.index("r_base_type.script_type = scr;"),
                        self.fn.index("r_base_type.script_path = scr->get_path();"))

    def test_missing_script_keeps_native_type_branch(self):
        self.assertRegex(self.fn, re.compile(
            r"if \(scr\.is_null\(\)\) \{\s*"
            r"r_base_type\.kind = GDScriptParser::DataType::NATIVE;"
            r"\s*\} else \{", re.S))

    def test_path_assignment_is_only_in_nonnull_branch(self):
        part = self.fn.split("if (scr.is_null()) {", 1)[1]
        native, scripted = part.split("} else {", 1)
        self.assertNotIn("script_path", native)
        self.assertIn("r_base_type.script_path = scr->get_path();", scripted)

    def test_no_duplicate_path_assignment(self):
        self.assertEqual(self.fn.count("r_base_type.script_path = scr->get_path();"), 1)


class WarningIgnoreContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        whole = source("editor/script/script_text_editor.cpp")
        cls.fn = whole.split("bool ScriptTextEditor::_warning_clicked(", 1)[1].split(
            "return false;", 1
        )[0]

    def test_warning_annotation_is_identified(self):
        self.assertIn('prev_line.contains("@warning_ignore")', self.fn)

    def test_existing_comment_must_be_excluded(self):
        self.assertIn("&& !text_editor->is_in_comment(line - 1, indent)", self.fn)

    def test_previous_line_is_guarded(self):
        self.assertIn("line > 0 ? text_editor->get_line(line - 1) : \"\"", self.fn)

    def test_indent_calculated_once_in_outer_branch(self):
        self.assertEqual(self.fn.count("const int indent = "), 1)

    def test_indentation_matches_editor_settings(self):
        self.assertIn("text_editor->get_indent_level(line) / text_editor->get_indent_size()", self.fn)

    def test_comment_guard_applies_before_editing_existing_annotation(self):
        guard = self.fn.index("!text_editor->is_in_comment(line - 1, indent)")
        insert = self.fn.index("text_editor->insert_text(")
        self.assertLess(guard, insert)

    def test_new_annotation_path_still_exists(self):
        self.assertIn("String annotation_indent;", self.fn)

    def test_previous_annotation_content_not_replaced(self):
        self.assertIn('const String text_to_insert = ", " + code.quote(quote_style);', self.fn)

    def test_not_reverted_to_original_unguarded_branch(self):
        self.assertNotIn('if (prev_line.contains("@warning_ignore")) {', self.fn)


class AnimationGroupingContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        whole = source("editor/animation/animation_track_editor.cpp")
        cls.toggle = whole.split("void AnimationTrackEditor::_view_group_toggle() {", 1)[1].split(
            "bool AnimationTrackEditor::is_grouping_tracks()", 1
        )[0]
        cls.constructor = whole.split("AnimationTrackEditor::AnimationTrackEditor() {", 1)[1]

    def test_grouping_choice_is_persisted(self):
        self.assertIn("set_project_metadata(", self.toggle)

    def test_grouping_choice_uses_pressed_state(self):
        self.assertIn('view_group->is_pressed());', self.toggle)

    def test_grouping_state_is_loaded(self):
        self.assertIn("view_group->set_pressed(EditorSettings::get_singleton()->get_project_metadata(", self.constructor)

    def test_persisted_and_loaded_settings_keys_match(self):
        key = '"animation_track_editor", "view_group_pressed"'
        self.assertIn(key, self.toggle)
        self.assertIn(key, self.constructor)

    def test_default_is_false_for_new_projects(self):
        self.assertIn('"animation_track_editor", "view_group_pressed", false)', self.constructor)

    def test_state_restored_after_toggle_enabled(self):
        self.assertLess(self.constructor.index("view_group->set_toggle_mode(true);"),
                        self.constructor.index("view_group->set_pressed(EditorSettings::get_singleton()->get_project_metadata("))

    def test_restoration_occurs_before_ui_is_shown(self):
        self.assertLess(self.constructor.index("view_group->set_pressed(EditorSettings::get_singleton()->get_project_metadata("),
                        self.constructor.index("view_group->set_tooltip_text("))

    def test_refresh_tracks_still_occurs(self):
        self.assertIn("_update_tracks();", self.toggle)

    def test_icon_still_reflects_toggle_state(self):
        self.assertIn('view_group->is_pressed() ? SNAME("AnimationTrackList") : SNAME("AnimationTrackGroup")',
                      self.toggle)

    def test_grouping_accessor_unchanged(self):
        self.assertIn("return !view_group->is_pressed();", source(
            "editor/animation/animation_track_editor.cpp"))


if __name__ == "__main__":
    unittest.main()
