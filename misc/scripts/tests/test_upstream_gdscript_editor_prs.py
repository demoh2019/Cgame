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



class VisualShaderGroupContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        whole = source("modules/visual_shader/editor/visual_shader_editor_plugin.cpp")
        cls.fn = whole.split("bool VisualShaderEditor::_is_type_disallowed_in_group_context(", 1)[1].split(
            "bool VisualShaderEditor::_group_would_create_cycle(", 1
        )[0]

    def test_builtin_input_not_allowed_in_groups(self):
        self.assertIn("p_type_name == VisualShaderNodeInput::get_class_static()", self.fn)

    def test_builtin_block_is_inside_group_condition(self):
        inside, outside = self.fn.split("} else {", 1)
        self.assertIn("if (p_is_inside_group)", inside)
        self.assertIn("VisualShaderNodeInput::get_class_static()", inside)
        self.assertNotIn("VisualShaderNodeInput::get_class_static()", outside)

    def test_group_ports_still_disallowed_outside_group(self):
        self.assertIn("p_type_name == VisualShaderNodeGroupInput::get_class_static()", self.fn)
        self.assertIn("p_type_name == VisualShaderNodeGroupOutput::get_class_static()", self.fn)


class ResourceSaveAsContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        whole = source("editor/editor_node.cpp")
        cls.fn = whole.split("void EditorNode::save_resource_as(", 1)[1].split(
            "bool EditorNode::is_resource_internal_to_scene(", 1
        )[0]

    def test_existing_resource_path_is_initialized(self):
        self.assertIn("String path = resource_path;", self.fn)

    def test_corrected_extension_is_applied_to_path(self):
        self.assertIn('path = resource_path.replacen("." + ext, "." + extensions.front()->get());', self.fn)

    def test_existing_resource_always_prefills_dialog(self):
        self.assertIn("file->set_current_path(path);", self.fn)
        self.assertLess(self.fn.index("String path = resource_path;"),
                        self.fn.index("file->set_current_path(path);"))

    def test_original_name_is_used_when_no_path(self):
        self.assertIn("file->set_current_file(new_resource_name_snake_case);", self.fn)


class EmbeddedWindowAlwaysOnTopContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        whole = source("scene/main/window.cpp")
        cls.fn = whole.split("void Window::set_flag(", 1)[1].split("bool Window::get_flag(", 1)[0]

    def test_subwindow_is_updated(self):
        self.assertIn("embedder->_sub_window_update(this);", self.fn)

    def test_always_on_top_reorders_embedded_windows(self):
        self.assertRegex(self.fn, re.compile(
            r"if \(p_flag == FLAG_ALWAYS_ON_TOP\) \{\s*"
            r"embedder->_sub_window_update_order\(\);", re.S))

    def test_reorder_occurs_after_update(self):
        self.assertLess(self.fn.index("embedder->_sub_window_update(this);"),
                        self.fn.index("embedder->_sub_window_update_order();"))


class GDScriptUnreachableContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        whole = source("modules/gdscript/gdscript_parser.cpp")
        cls.statement = whole.split("GDScriptParser::Node *GDScriptParser::parse_statement() {", 1)[1].split(
            "GDScriptParser::AssertNode *GDScriptParser::parse_assert()", 1
        )[0]
        cls.parse_break = whole.split("GDScriptParser::BreakNode *GDScriptParser::parse_break() {", 1)[1].split(
            "GDScriptParser::ContinueNode *GDScriptParser::parse_continue()", 1
        )[0]
        cls.parse_if = whole.split("GDScriptParser::IfNode *GDScriptParser::parse_if(", 1)[1].split(
            "GDScriptParser::MatchNode *GDScriptParser::parse_match()", 1
        )[0]

    def test_break_and_continue_trigger_unreachable_detection(self):
        self.assertIn("current_suite->has_continue || current_suite->has_break", self.statement)
        self.assertIn("current_suite->has_break = true;", self.parse_break)

    def test_warning_identifies_terminator(self):
        for word in ("return", "continue", "break"):
            self.assertIn('end_statement_name = "\\"' + word + '\\"";', self.statement)

    def test_conditional_continue_does_not_poison_parent_block(self):
        self.assertNotIn("current_suite->has_continue = true;", self.parse_if)

    def test_updated_warning_message_accepts_two_symbols(self):
        warn = source("modules/gdscript/gdscript_warning.cpp")
        item = warn.split("case UNREACHABLE_CODE:", 1)[1].split("case UNREACHABLE_PATTERN:", 1)[0]
        self.assertIn("CHECK_SYMBOLS(2)", item)
        self.assertIn("symbols[0], symbols[1]", item)

    def test_gdscript_fixtures_have_expected_outputs(self):
        base = "modules/gdscript/tests/scripts/parser/warnings/"
        names = (
            "unreachable_code_after_break",
            "unreachable_code_after_continue",
            "unreachable_code_conditional_continue",
            "unreachable_code_conditional_break",
            "unreachable_code_once_per_block",
        )
        for name in names:
            with self.subTest(name=name):
                gd = source(base + name + ".gd")
                out = source(base + name + ".out")
                self.assertIn("func test():", gd)
                self.assertTrue(out.startswith("GDTEST_OK\n"))
                if name.startswith("unreachable_code_conditional"):
                    self.assertNotIn("UNREACHABLE_CODE", out)
                else:
                    self.assertEqual(out.count("UNREACHABLE_CODE"), 1)




class Path3DGizmoContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cpp = source("editor/scene/3d/path_3d_editor_plugin.cpp")
        cls.fn = cpp.split("void Path3DGizmo::_update_transform_gizmo() {", 1)[1].split(
            "EditorPlugin::AfterGUIInput Path3DEditorPlugin::forward_3d_gui_input(", 1
        )[0]
        cls.header = source("editor/scene/3d/path_3d_editor_plugin.h")

    def test_cached_point_count_is_declared(self):
        self.assertIn("int cached_point_count = 0;", self.header)

    def test_constructor_caches_initial_curve_point_count(self):
        self.assertIn("cached_point_count = curve.is_valid() ? curve->get_point_count() : 0;", self.fn)

    def test_stale_selection_is_cleared_on_null_curve(self):
        self.assertIn("curve.is_null() || point_count != cached_point_count", self.fn)
        self.assertIn("clear_subgizmo_selection(path);", self.fn)

    def test_point_count_is_updated_before_clearing_selection(self):
        self.assertLess(self.fn.index("cached_point_count = point_count;"),
                        self.fn.index("clear_subgizmo_selection(path);"))

    def test_existing_transform_refresh_remains(self):
        self.assertIn("Node3DEditor::get_singleton()->update_transform_gizmo();", self.fn)


class Audio3DMixCountContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cpp = source("scene/3d/audio_stream_player_3d.cpp")
        cls.fn = cpp.split("case NOTIFICATION_INTERNAL_PHYSICS_PROCESS:", 1)[1].split(
            "if (setplayback.is_valid()", 1
        )[0]

    def test_zero_time_playback_triggers_panning(self):
        self.assertIn("setplay.get() >= 0", self.fn)

    def test_panning_refreshes_mix_count(self):
        self.assertIn("last_mix_count = AudioServer::get_singleton()->get_mix_count();", self.fn)

    def test_mix_count_is_refreshed_after_panning(self):
        self.assertLess(self.fn.index("volume_vector = _update_panning();"),
                        self.fn.index("last_mix_count = AudioServer::get_singleton()->get_mix_count();"))



if __name__ == "__main__":
    unittest.main()
