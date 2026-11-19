"""Regression checks for O(N) rather than O(N²) result-label refresh during replace-all."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
SRC = (ROOT / "editor/script/find_in_files.cpp").read_text(encoding="utf-8")
HDR = (ROOT / "editor/script/find_in_files.h").read_text(encoding="utf-8")


def body(signature):
    start = SRC.index(signature)
    return SRC[start:SRC.index("\n}\n", start) + 2]


class ReplaceAllCostTests(unittest.TestCase):
    def test_helper_accepts_label_update_flag(self):
        self.assertIn("void _remove_result(TreeItem *p_item, bool p_update_matches);", HDR)

    def test_implementation_matches_declaration(self):
        self.assertIn("void FindInFilesResultsPanel::_remove_result(TreeItem *p_item, bool p_update_matches)", SRC)

    def test_helper_skips_label_refresh_if_disabled(self):
        b = body("void FindInFilesResultsPanel::_remove_result(")
        self.assertIn("if (p_update_matches) {", b)
        self.assertIn("_update_matches_text();", b)

    def test_helper_still_removes_result_items(self):
        b = body("void FindInFilesResultsPanel::_remove_result(")
        self.assertIn("result_items.erase(p_item);", b)
        self.assertIn("get_tree()->queue_delete(p_item);", b)

    def test_batch_loop_defers_label_refresh(self):
        b = body("void FindInFilesResultsPanel::replace_all()")
        self.assertIn("for (TreeItem *item : replaced_items) {\n\t\t_remove_result(item, false);", b)

    def test_batch_calls_label_refresh_exactly_once(self):
        b = body("void FindInFilesResultsPanel::replace_all()")
        self.assertEqual(b.count("_update_matches_text();"), 1)
        self.assertLess(b.index("_remove_result(item, false);"), b.index("_update_matches_text();"))

    def test_non_batch_click_still_refreshes_label(self):
        b = body("void FindInFilesResultsPanel::_on_button_clicked(")
        self.assertIn("_remove_result(p_item, true);", b)

    def test_batch_keeps_modified_files_signal(self):
        b = body("void FindInFilesResultsPanel::replace_all()")
        self.assertIn('emit_signal(SNAME("files_modified"));', b)
        self.assertGreater(b.index('emit_signal(SNAME("files_modified"));'), b.index("_update_matches_text();"))

    def test_batch_preserves_replace_files_operation(self):
        self.assertIn("_apply_replaces_in_file(fpath, locations, replace_text);", body("void FindInFilesResultsPanel::replace_all()"))

    def test_in_place_replacement_still_updates_filesystem(self):
        b = body("void FindInFilesResultsPanel::_apply_replaces_in_file(")
        self.assertIn("EditorFileSystem::get_singleton()->update_file(p_fpath);", b)
        self.assertIn("res->reload_from_file();", b)

    def test_all_calls_use_explicit_update_flag(self):
        self.assertEqual(SRC.count("_remove_result("), 3)
        self.assertEqual(SRC.count("_remove_result(item, false);"), 1)
        self.assertEqual(SRC.count("_remove_result(p_item, true);"), 1)


if __name__ == "__main__":
    unittest.main()
