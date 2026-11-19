"""Source-level contracts for editor project sorting and bulk text replacement."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
PROJECT = (ROOT / "editor/project_manager/project_list.cpp").read_text(encoding="utf-8")
FIND = (ROOT / "editor/script/find_in_files.cpp").read_text(encoding="utf-8")
SORT = PROJECT.split("void ProjectList::sort_projects() {", 1)[1].split("int ProjectList::get_project_count()", 1)[0]
ICON = PROJECT.split("case NOTIFICATION_PROCESS: {", 1)[1].split("} break;", 1)[0]
REPLACE = FIND.split("void FindInFilesResultsPanel::_apply_replaces_in_file(", 1)[1].split(
    "void FindInFilesResultsPanel::_update_matches_text()", 1)[0]


class EditorBatchFastpathContracts(unittest.TestCase):
    def test_sort_avoids_write_access_for_read_only_project_items(self):
        self.assertNotIn("_projects.write[i]", SORT)
        self.assertEqual(SORT.count("const Item &item = _projects[i];"), 2)

    def test_search_full_path_decision_is_computed_once(self):
        self.assertEqual(SORT.count("search_term.contains_char('/')"), 1)
        self.assertIn("if (search_full_path)", SORT)

    def test_move_child_is_called_only_for_out_of_order_controls(self):
        self.assertIn("if (item.control->get_index() != i)", SORT)
        self.assertLess(SORT.index("if (item.control->get_index() != i)"), SORT.index("move_child(item.control, i)"))

    def test_filter_logic_remains_intact(self):
        self.assertIn("item.project_name.containsn(search_term)", SORT)
        self.assertIn("search_path.containsn(search_term)", SORT)
        self.assertIn("item.tags.has(tag)", SORT)

    def test_icon_queue_does_not_detach_project_vector_for_read(self):
        self.assertNotIn("_projects.write[_icon_load_index]", ICON)
        self.assertIn("const Item &item = _projects[_icon_load_index];", ICON)

    def test_find_in_files_writable_pointer_is_acquired_once(self):
        self.assertEqual(REPLACE.count("String *lines_write = lines.ptrw();"), 1)
        self.assertNotIn("lines.write[repl_line_number]", REPLACE)

    def test_replacements_remain_reverse_ordered(self):
        self.assertIn("for (int i = p_locations.size() - 1; i >= 0; i--)", REPLACE)
        self.assertIn("String &line = lines_write[repl_line_number];", REPLACE)
        self.assertLess(REPLACE.index("String *lines_write = lines.ptrw();"), REPLACE.index("for (int i = p_locations.size() - 1;"))

    def test_edited_lines_use_original_matching_rules(self):
        self.assertIn("find_next(line, search_text, location.begin", REPLACE)
        self.assertIn("line = line.left(location.begin) + p_new_text + line.substr(location.end);", REPLACE)


if __name__ == "__main__":
    unittest.main()
