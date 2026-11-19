"""Source-regression guards for upstream godotengine/godot#125616.

Run from repository root:
    python3 -m unittest discover -s misc/scripts/tests -p test_upstream_external_change_dialog.py -v

This validates the editor dialog wiring without requiring a graphical display.
Native GUI interaction / full Godot build remains a separate validation step.
"""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[3]
SOURCE = (ROOT / "editor/editor_node.cpp").read_text(encoding="utf-8")
HEADER = (ROOT / "editor/editor_node.h").read_text(encoding="utf-8")


def extract_cpp_body(signature):
    start = SOURCE.index(signature)
    opening = SOURCE.index("{", start)
    depth = 0
    for index in range(opening, len(SOURCE)):
        if SOURCE[index] == "{":
            depth += 1
        elif SOURCE[index] == "}":
            depth -= 1
            if depth == 0:
                return SOURCE[opening + 1 : index]
    raise AssertionError(f"Unterminated method: {signature}")


class ExternalChangeDialogRegressionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.creator = extract_cpp_body("ConfirmationDialog *EditorNode::_create_disk_changed_dialog()")
        cls.scan = extract_cpp_body("void EditorNode::_scan_external_changes()")
        cls.restore = extract_cpp_body("void EditorNode::_restore_disk_changed_dialog_parent()")
        cls.save = extract_cpp_body("void EditorNode::_resave_externally_modified_scenes(String p_str)")
        cls.reload = extract_cpp_body("void EditorNode::_reload_modified_scenes()")
        cls.constructor = extract_cpp_body("EditorNode::EditorNode()")

    def test_dialog_is_tracked_by_id_not_dangling_pointer(self):
        self.assertIn("ObjectID disk_changed;", HEADER)
        self.assertNotIn("ConfirmationDialog *disk_changed =", HEADER)

    def test_helpers_are_declared(self):
        self.assertIn("ConfirmationDialog *_create_disk_changed_dialog();", HEADER)
        self.assertIn("void _restore_disk_changed_dialog_parent();", HEADER)

    def test_foreground_scan_is_deferred_after_focus_return(self):
        self.assertIn(
            "callable_mp(this, &EditorNode::_scan_external_changes).call_deferred();",
            SOURCE,
        )

    def test_constructor_does_not_eagerly_create_modal(self):
        self.assertNotIn("disk_changed = memnew(ConfirmationDialog)", self.constructor)

    def test_creating_dialog_attaches_to_gui_base(self):
        self.assertIn("ConfirmationDialog *dialog = memnew(ConfirmationDialog);", self.creator)
        self.assertIn("gui_base->add_child(dialog);", self.creator)

    def test_created_dialog_is_referenced_by_instance_id(self):
        self.assertIn("disk_changed = dialog->get_instance_id();", self.creator)
        self.assertIn("return dialog;", self.creator)

    def test_scan_recovers_from_deleted_modal(self):
        self.assertIn("ObjectDB::get_instance<ConfirmationDialog>(disk_changed)", self.scan)
        self.assertRegex(self.scan, r"if \(!dialog\) \{\s*dialog = _create_disk_changed_dialog\(\);\s*\}")

    def test_scan_uses_valid_dialog_before_touching_entries(self):
        self.assertLess(self.scan.index("_create_disk_changed_dialog()"), self.scan.index("disk_changed_list->clear();"))

    def test_scan_does_not_popup_an_already_visible_dialog(self):
        self.assertIn("if (need_reload && !dialog->is_visible())", self.scan)

    def test_popup_parent_follows_last_exclusive_window(self):
        self.assertIn("Window *window = get_last_exclusive_window();", self.scan)
        self.assertIn("window == get_window() ? static_cast<Node *>(gui_base) : window", self.scan)
        self.assertIn("dialog->reparent(popup_parent);", self.scan)

    def test_dialog_is_shown_only_after_reparent(self):
        self.assertLess(self.scan.index("dialog->reparent(popup_parent);"), self.scan.index("dialog->popup_centered_ratio(0.3);"))

    def test_restore_is_connected_using_deferred_visibility_signal(self):
        self.assertIn("SceneStringName(visibility_changed)", self.creator)
        self.assertIn("EditorNode::_restore_disk_changed_dialog_parent", self.creator)
        self.assertIn("CONNECT_DEFERRED", self.creator)

    def test_restore_is_guarded_against_freed_or_visible_dialog(self):
        self.assertIn("ObjectDB::get_instance<ConfirmationDialog>(disk_changed)", self.restore)
        self.assertIn("dialog && !dialog->is_visible() && gui_base->is_inside_tree()", self.restore)
        self.assertIn("dialog->reparent(gui_base);", self.restore)

    def test_ignore_external_changes_uses_liveness_checked_hide(self):
        self.assertRegex(self.save, r"if \(ConfirmationDialog \*dialog = ObjectDB::get_instance<ConfirmationDialog>\(disk_changed\)\) \{\s*dialog->hide\(\);")

    def test_reload_external_scenes_uses_liveness_checked_hide(self):
        self.assertRegex(self.reload, r"if \(ConfirmationDialog \*dialog = ObjectDB::get_instance<ConfirmationDialog>\(disk_changed\)\) \{\s*dialog->hide\(\);")

    def test_dialog_still_supports_reload_and_ignore_actions(self):
        self.assertIn("&EditorNode::_reload_modified_scenes", self.creator)
        self.assertIn("&EditorNode::_reload_project_settings", self.creator)
        self.assertIn("&EditorNode::_resave_externally_modified_scenes", self.creator)

    def test_editor_translation_keys_remain_extracted(self):
        for message in (
            "Files have been modified outside Godot",
            "The following files are newer on disk:",
            "What action should be taken?",
            "Reload from disk",
            "Ignore external changes",
        ):
            with self.subTest(message=message):
                self.assertIn(f'TTRC("{message}")', self.creator)

    def test_no_legacy_pointer_dereferences(self):
        self.assertNotIn("disk_changed->", SOURCE)
        self.assertNotIn("callable_mp((Window *)disk_changed", SOURCE)


if __name__ == "__main__":
    unittest.main()
