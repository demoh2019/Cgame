"""Regression contracts for Godot upstream #125479 (scene-aware symbol rename).

These are source-level safeguards, not a substitute for compiling the engine
and performing interactive renaming in the editor.
"""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "editor/script/find_in_files.cpp"


def get_body(text: str, marker: str, next_marker: str) -> str:
    if text.count(marker) != 1:
        raise AssertionError(f"Expected exactly one {marker}, got {text.count(marker)}")
    body = text.split(marker, 1)[1]
    if next_marker not in body:
        raise AssertionError(f"Missing delimiter after {marker}")
    return body.split(next_marker, 1)[0]


class SceneAwareSymbolRenameTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = SOURCE.read_text(encoding="utf-8")
        cls.create = get_body(
            cls.source,
            "void FindInFilesContainer::create_rename_control(",
            "void FindInFilesResultsPanel::_notification(",
        )
        cls.found = get_body(
            cls.source,
            "void FindInFilesResultsPanel::_on_result_found(",
            "void FindInFilesResultsPanel::_on_theme_changed(",
        )

    # Search scope: only exported script properties should add .tscn files.
    def test_rename_loads_target_script(self):
        self.assertIn("Ref<Script> scr = ResourceLoader::load(p_lookup.script_path);", self.create)

    def test_script_load_is_checked(self):
        self.assertIn("ERR_FAIL_COND(scr.is_null());", self.create)

    def test_script_extension_remains_searchable(self):
        self.assertIn("exts.insert(scr->get_language()->get_extension());", self.create)

    def test_only_class_properties_can_add_scenes(self):
        self.assertIn("if (p_lookup.type == EditorLanguage::LookupResult::Type::CLASS_PROPERTY)", self.create)

    def test_script_property_list_is_consulted(self):
        self.assertIn("get_script_property_list(&script_properties);", self.create)

    def test_property_iteration_is_present(self):
        self.assertIn("for (const PropertyInfo &pi : script_properties)", self.create)

    def test_matching_property_name_is_required(self):
        self.assertIn("if (pi.name == p_symbol)", self.create)

    def test_storage_usage_is_required(self):
        self.assertIn("if (pi.usage & PROPERTY_USAGE_STORAGE)", self.create)

    def test_scene_extension_added_under_property_check(self):
        self.assertRegex(
            self.create,
            re.compile(
                r"if \(pi\.name == p_symbol\) \{\s*"
                r"if \(pi\.usage & PROPERTY_USAGE_STORAGE\) \{\s*"
                r"//[^\n]*\n\s*exts\.insert\(\"tscn\"\);",
                re.S,
            ),
        )

    def test_only_first_matching_property_matters(self):
        self.assertRegex(self.create, re.compile(
            r"exts\.insert\(\"tscn\"\);\s*\}\s*break;"))
    def test_script_extension_not_replaced_by_scene_extension(self):
        self.assertLess(
            self.create.index("exts.insert(scr->get_language()->get_extension());"),
            self.create.index('exts.insert("tscn");'),
        )

    def test_filter_is_applied_from_extension_set(self):
        self.assertIn("finder->set_filter(exts);", self.create)

    def test_search_remains_case_sensitive(self):
        self.assertIn("finder->set_match_case(true);", self.create)

    def test_search_remains_whole_word(self):
        self.assertIn("finder->set_whole_words(true);", self.create)

    def test_symbol_rename_context_preserved(self):
        self.assertIn("finder->set_symbol_rename(p_lookup);", self.create)

    def test_controls_do_not_emit_partial_searches(self):
        self.assertIn("search_control->set_block_signals(true);", self.create)
        self.assertIn("search_control->set_block_signals(false);", self.create)

    def test_result_panel_receives_lookup(self):
        self.assertIn("new_panel->set_symbol_rename(p_lookup);", self.create)

    def test_search_is_explicitly_started(self):
        self.assertIn("new_panel->start_search();", self.create)

    # Result validation: scene matches only at the property-name column.
    def test_scene_detection_uses_extension(self):
        self.assertIn('bool is_scene = p_fpath.has_extension("tscn");', self.found)

    def test_rename_mode_uses_script_path(self):
        self.assertIn("bool is_renaming = !symbol_rename.script_path.is_empty();", self.found)

    def test_non_property_column_scene_match_is_skipped(self):
        self.assertIn("if (is_renaming && is_scene && p_begin > 0)", self.found)

    def test_skipped_scene_occurrence_returns_before_result_creation(self):
        self.assertLess(
            self.found.index("if (is_renaming && is_scene && p_begin > 0)"),
            self.found.index("results_display->create_item()"),
        )

    def test_normal_search_does_not_skip_scene_matches(self):
        # The guard is explicitly dependent on is_renaming.
        self.assertRegex(self.found, re.compile(
            r"if \(is_renaming && is_scene && p_begin > 0\) \{\s*return;\s*\}"
        ))

    def test_script_validation_is_excluded_for_scenes(self):
        self.assertIn("if (is_renaming) {\n\t\t\tif (!is_scene) {", self.found)

    def test_script_validation_still_uses_language_aware_lookup(self):
        self.assertIn("lookup_code_for_rename(", self.found)

    def test_script_validation_checks_matching_definition(self):
        self.assertIn("result.class_member == symbol_rename.class_member", self.found)
        self.assertIn("result.script_path == symbol_rename.script_path", self.found)
        self.assertIn("result.location == symbol_rename.location", self.found)

    def test_missing_script_reports_error(self):
        self.assertIn('ERR_PRINT(vformat("Failed to load Script at', self.found)

    def test_scene_matches_not_automatically_selected(self):
        self.assertRegex(
            self.found,
            re.compile(
                r"bool check_item = false;\s*"
                r"if \(is_renaming\) \{\s*"
                r"if \(!is_scene\) \{", re.S,
            ),
        )

    def test_normal_replace_results_remain_checked(self):
        self.assertIn("} else {\n\t\t\tcheck_item = true;\n\t\t}", self.found)

    def test_checkbox_uses_computed_safe_default(self):
        self.assertIn("item->set_checked(0, check_item);", self.found)

    def test_item_still_editable_for_manual_approval(self):
        self.assertIn("item->set_editable(0, true);", self.found)

    def test_replace_button_retained(self):
        self.assertIn('item->add_button(1, replace_texture, FIND_BUTTON_REPLACE', self.found)

    def test_earlier_find_filter_regression_not_reverted(self):
        self.assertIn("finder->set_filter(get_filter());", self.source)

    def test_earlier_rename_mode_guard_not_reverted(self):
        self.assertIn("if (finder->is_rename_mode())", self.source)

    def test_no_auto_rewrite_in_initial_search_setup(self):
        self.assertNotIn("FileAccess::open(", self.create)
        self.assertNotIn("ResourceSaver::save(", self.create)


if __name__ == "__main__":
    unittest.main()
