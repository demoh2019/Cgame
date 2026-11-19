"""Source-level contract tests for incremental project manager folder scanning.

These tests guard the hot-path structure; a native editor build and GUI smoke test
are still required to validate the runtime control tree.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
SOURCE = (ROOT / "editor/project_manager/project_list.cpp").read_text(encoding="utf-8")
START = SOURCE.index("void ProjectList::_scan_finished()")
END = SOURCE.index("// Initialization & loading.", START)
BODY = SOURCE[START:END]


class IncrementalProjectScanTests(unittest.TestCase):
    def test_waits_for_scan_thread_before_touching_results(self):
        self.assertLess(BODY.index("wait_to_finish()"), BODY.index("found_projects"))

    def test_scan_is_cancelable(self):
        self.assertIn("scan_in_progress.clear()", BODY)

    def test_progress_dialog_still_hides(self):
        self.assertIn("scan_progress->hide()", BODY)

    def test_does_not_reload_all_projects(self):
        self.assertNotIn("update_project_list(", BODY)
        self.assertNotIn("load_project_list(", BODY)

    def test_scans_only_found_project_paths(self):
        self.assertRegex(BODY, r"for \(const String &path : scan_data->found_projects\)")

    def test_deduplicates_against_existing_project_paths(self):
        self.assertIn("HashSet<String> known_paths;", BODY)
        self.assertIn("for (const Item &project : _projects)", BODY)
        self.assertIn("known_paths.insert(project.path);", BODY)
        self.assertRegex(BODY, r"if \(known_paths.size\(\) == previous_count\)\s*\{\s*continue;")

    def test_deduplication_precedes_allocation_and_writes(self):
        self.assertLess(BODY.index("known_paths.insert(path);"), BODY.index("add_project(path, false)"))
        self.assertLess(BODY.index("if (known_paths.size() == previous_count)"), BODY.index("load_project_data(path, false)"))

    def test_existing_paths_are_indexed_once_before_scanning_discovered_paths(self):
        self.assertLess(BODY.index("for (const Item &project : _projects)"), BODY.index("for (const String &path : scan_data->found_projects)"))
        self.assertNotRegex(BODY, r"for \(const String &path : scan_data->found_projects\)[\s\S]*for \(const Item &project : _projects\)")

    def test_hash_set_is_reserved_at_known_upper_bound(self):
        self.assertIn("known_paths.reserve(_projects.size() + scan_data->found_projects.size());", BODY)
        self.assertIn("if (!scan_data->found_projects.is_empty())", BODY)

    def test_duplicates_in_single_scan_do_not_create_two_controls(self):
        self.assertLess(BODY.index("const uint32_t previous_count = known_paths.size();"), BODY.index("known_paths.insert(path);"))
        self.assertLess(BODY.index("known_paths.insert(path);"), BODY.index("if (known_paths.size() == previous_count)"))
        self.assertLess(BODY.index("if (known_paths.size() == previous_count)"), BODY.index("_create_project_item_control(_projects.size() - 1);")))

    def test_only_creates_new_controls(self):
        self.assertIn("_projects.push_back(load_project_data(path, false));", BODY)
        self.assertIn("_create_project_item_control(_projects.size() - 1);", BODY)

    def test_existing_selection_is_not_cleared(self):
        self.assertNotIn("_selected_project_paths.clear()", BODY)
        self.assertNotIn("_last_clicked = ", BODY)

    def test_releases_scan_data_even_when_empty(self):
        self.assertLess(BODY.index("memdelete(scan_data)"), BODY.index("if (!edited)"))
        self.assertLess(BODY.index("scan_data = nullptr"), BODY.index("if (!edited)"))

    def test_noop_scan_avoids_config_save_and_resort(self):
        self.assertRegex(BODY, r"if \(!edited\)\s*\{\s*return;\s*\}")
        self.assertLess(BODY.index("if (!edited)"), BODY.index("save_config()"))
        self.assertLess(BODY.index("if (!edited)"), BODY.index("sort_projects()"))

    def test_single_resort_for_added_items(self):
        self.assertEqual(BODY.count("sort_projects();"), 1)
        self.assertGreater(BODY.index("sort_projects()"), BODY.index("scan_data = nullptr"))

    def test_notifies_project_manager_after_update(self):
        self.assertLess(BODY.index("sort_projects()"), BODY.index("emit_signal(SNAME(SIGNAL_LIST_CHANGED))"))
        self.assertIn("set_v_scroll(0)", BODY)


if __name__ == "__main__":
    unittest.main()
