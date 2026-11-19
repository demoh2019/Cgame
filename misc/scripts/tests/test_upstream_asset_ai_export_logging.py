"""Source-contract checks for adopted Godot PRs #125409 and #125447.

These tests deliberately read the engine source checked out by CI. They ensure
the filter choices, query wiring and export warning behavior are not regressed.
A full native build and manual editor tests are still needed.
"""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[3]


def cpp(path):
    return (ROOT / path).read_text(encoding="utf-8")


def function_body(text, function_name):
    marker = function_name + " {"
    if text.count(marker) != 1:
        raise AssertionError(f"Missing or ambiguous function: {function_name}")
    # The next function starts on a new unindented line.
    return text.split(marker, 1)[1].split("\n}\n", 1)[0]


class AssetLibraryAIPreferenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.code = cpp("editor/asset_library/asset_library_editor_plugin.cpp")
        cls.header = cpp("editor/asset_library/asset_library_editor_plugin.h")
        cls.search = function_body(cls.code, "void EditorAssetLibrary::_search(int p_page)")
        cls.constructor = cls.code.split(
            "EditorAssetLibrary::EditorAssetLibrary(bool p_templates_only) {", 1
        )[1]

    def test_option_member_is_declared(self):
        self.assertIn("OptionButton *uses_ai = nullptr;", self.header)

    def test_option_member_stays_adjacent_to_category_and_repo(self):
        self.assertRegex(self.header, re.compile(
            r"OptionButton \*categories = nullptr;\s*"
            r"OptionButton \*uses_ai = nullptr;\s*"
            r"OptionButton \*repository = nullptr;"
        ))

    def test_filter_control_is_created(self):
        self.assertIn("uses_ai = memnew(OptionButton);", self.constructor)

    def test_filter_label_is_translatable(self):
        self.assertIn('Label(TTRC("Uses AI:"))', self.constructor)

    def test_default_is_no_preference(self):
        self.assertIn('uses_ai->add_item(TTRC("No Preference"));', self.constructor)

    def test_default_omits_query_parameter(self):
        self.assertIn('uses_ai->set_item_metadata(-1, "");', self.constructor)

    def test_ai_only_option_is_present(self):
        self.assertIn('uses_ai->add_item(TTRC("Uses AI"));', self.constructor)

    def test_ai_only_sends_true(self):
        self.assertIn('uses_ai->set_item_metadata(-1, "True");', self.constructor)

    def test_without_ai_option_is_present(self):
        self.assertIn('uses_ai->add_item(TTRC("No AI"));', self.constructor)

    def test_without_ai_sends_false(self):
        self.assertIn('uses_ai->set_item_metadata(-1, "False");', self.constructor)

    def test_choices_in_stable_order(self):
        terms = [
            'uses_ai->add_item(TTRC("No Preference"));',
            'uses_ai->add_item(TTRC("Uses AI"));',
            'uses_ai->add_item(TTRC("No AI"));',
        ]
        positions = [self.constructor.index(x) for x in terms]
        self.assertEqual(positions, sorted(positions))

    def test_all_three_choices_have_metadata(self):
        self.assertEqual(self.constructor.count("uses_ai->set_item_metadata(-1,"), 3)

    def test_option_is_attached_to_search_bar(self):
        self.assertIn("search_hb2->add_child(uses_ai);", self.constructor)

    def test_option_is_responsive_in_narrow_layouts(self):
        self.assertIn("uses_ai->set_clip_text(true);", self.constructor)
        self.assertIn("uses_ai->set_fit_to_longest_item(false);", self.constructor)

    def test_selection_reruns_search(self):
        self.assertIn(
            "uses_ai->connect(SceneStringName(item_selected), "
            "callable_mp(this, &EditorAssetLibrary::_search).bind(1).unbind(1));",
            self.constructor,
        )

    def test_filter_position_before_repository(self):
        self.assertLess(
            self.constructor.index("search_hb2->add_child(uses_ai);"),
            self.constructor.index("repository = memnew(OptionButton);"),
        )

    def test_selected_metadata_is_read(self):
        self.assertIn("String ai = uses_ai->get_selected_metadata();", self.search)

    def test_parameter_added_only_when_filter_enabled(self):
        self.assertRegex(
            self.search,
            re.compile(
                r'if \(!ai\.is_empty\(\)\) \{\s*'
                r'args \+= "&uses_ai=" \+ ai;\s*\}',
                re.S,
            ),
        )

    def test_unfiltered_search_retains_text_search(self):
        self.assertIn("String args = \"?query=\" + search.uri_encode();", self.search)

    def test_unfiltered_search_retains_sort(self):
        self.assertIn('args += "&sort=" + String(sort_key[sort->get_selected()]);', self.search)

    def test_filter_is_not_forced_for_incompatible_assets(self):
        self.assertLess(
            self.search.index('args += "&uses_ai=" + ai;'),
            self.search.index('EDITOR_GET("asset_store/show_incompatible_assets")'),
        )

    def test_filter_never_changes_local_assets(self):
        self.assertNotIn("ResourceLoader::load(", self.search)


class ExportDebugSymbolLoggingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.pc = cpp("editor/export/editor_export_platform_pc.cpp")
        cls.mac = cpp("platform/macos/export/export_plugin.cpp")

    def test_pc_executable_debug_ids_are_verbose_only(self):
        self.assertIn('print_verbose("Executable debug IDs: " + String(", ").join(exec_debug_ids));', self.pc)

    def test_pc_symbols_debug_ids_are_verbose_only(self):
        self.assertIn('print_verbose("Symbols debug IDs: " + String(", ").join(symb_debug_ids));', self.pc)

    def test_macos_executable_debug_ids_are_verbose_only(self):
        self.assertIn('print_verbose("Executable debug IDs: " + String(", ").join(exec_debug_ids));', self.mac)

    def test_macos_symbols_debug_ids_are_verbose_only(self):
        self.assertIn('print_verbose("Symbols debug IDs: " + String(", ").join(symb_debug_ids));', self.mac)

    def test_pc_never_emits_ids_at_regular_log_level(self):
        self.assertNotIn('print_line("Executable debug IDs: ", exec_debug_ids);', self.pc)
        self.assertNotIn('print_line("Symbols debug IDs: ", symb_debug_ids);', self.pc)

    def test_macos_never_emits_ids_at_regular_log_level(self):
        self.assertNotIn('print_line("Executable debug IDs: ", exec_debug_ids);', self.mac)
        self.assertNotIn('print_line("Symbols debug IDs: ", symb_debug_ids);', self.mac)

    def test_pc_mismatch_warning_is_preserved(self):
        self.assertIn("if (exec_debug_ids != symb_debug_ids)", self.pc)
        self.assertIn("EXPORT_MESSAGE_WARNING", self.pc)
        self.assertIn("Executable and symbols debug ID mismatch", self.pc)

    def test_macos_mismatch_warning_is_preserved(self):
        self.assertIn("if (id_match != exec_debug_ids.size())", self.mac)
        self.assertIn("EXPORT_MESSAGE_WARNING", self.mac)
        self.assertIn("Executable and symbols debug ID mismatch", self.mac)

    def test_pc_still_reads_both_build_ids(self):
        self.assertIn("get_debug_build_id(p_path);", self.pc)
        self.assertIn('get_debug_build_id(p_path + ".debugsymbols");', self.pc)

    def test_macos_still_checks_partial_universal_symbols(self):
        self.assertIn("if (id_match != exec_debug_ids.size())", self.mac)


if __name__ == "__main__":
    unittest.main()
