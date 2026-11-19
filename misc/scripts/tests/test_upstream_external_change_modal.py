"""Source-contract regressions for Godot upstream PR #125616.

The real modal UI must also be verified in an editor run; these checks
guard lifetime, translation, and deferred-popup behavior between builds.
"""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
CPP = (ROOT / "editor/editor_node.cpp").read_text(encoding="utf-8")
HDR = (ROOT / "editor/editor_node.h").read_text(encoding="utf-8")


def section(start, end):
    return CPP.split(start, 1)[1].split(end, 1)[0]


class ExternalChangeDialogContracts(unittest.TestCase):
    def test_object_id_replaces_owning_raw_pointer(self):
        self.assertIn("ObjectID disk_changed;", HDR)

    def test_no_raw_pointer_field(self):
        self.assertNotIn("ConfirmationDialog *disk_changed =", HDR)

    def test_factory_declared_in_header(self):
        self.assertIn("ConfirmationDialog *_create_disk_changed_dialog();", HDR)

    def test_restore_declared_in_header(self):
        self.assertIn("void _restore_disk_changed_dialog_parent();", HDR)

    def test_external_scan_deferred_during_notification(self):
        self.assertIn("callable_mp(this, &EditorNode::_scan_external_changes).call_deferred();", CPP)

    def test_factory_creates_dialog_lazily(self):
        factory = section("ConfirmationDialog *EditorNode::_create_disk_changed_dialog() {",
                          "void EditorNode::_scan_external_changes() {")
        self.assertIn("memnew(ConfirmationDialog)", factory)

    def test_factory_records_dialog_id(self):
        factory = section("ConfirmationDialog *EditorNode::_create_disk_changed_dialog() {",
                          "void EditorNode::_scan_external_changes() {")
        self.assertIn("disk_changed = dialog->get_instance_id();", factory)

    def test_factory_retains_reload_and_ignore_actions(self):
        factory = section("ConfirmationDialog *EditorNode::_create_disk_changed_dialog() {",
                          "void EditorNode::_scan_external_changes() {")
        for action in ("_reload_modified_scenes", "_reload_project_settings",
                       "_resave_externally_modified_scenes"):
            with self.subTest(action=action):
                self.assertIn(action, factory)

    def test_dialog_hides_restore_to_deferred_callback(self):
        factory = section("ConfirmationDialog *EditorNode::_create_disk_changed_dialog() {",
                          "void EditorNode::_scan_external_changes() {")
        self.assertIn("SceneStringName(visibility_changed)", factory)
        self.assertIn("CONNECT_DEFERRED", factory)

    def test_existing_dialog_id_is_checked(self):
        scan = section("void EditorNode::_scan_external_changes() {",
                       "void EditorNode::_restore_disk_changed_dialog_parent() {")
        self.assertIn("ObjectDB::get_instance<ConfirmationDialog>(disk_changed)", scan)
        self.assertIn("if (!dialog)", scan)
        self.assertIn("_create_disk_changed_dialog();", scan)

    def test_visible_dialog_is_not_shown_twice(self):
        scan = section("void EditorNode::_scan_external_changes() {",
                       "void EditorNode::_restore_disk_changed_dialog_parent() {")
        self.assertIn("if (need_reload && !dialog->is_visible())", scan)

    def test_popup_attaches_to_last_exclusive_window(self):
        scan = section("void EditorNode::_scan_external_changes() {",
                       "void EditorNode::_restore_disk_changed_dialog_parent() {")
        self.assertIn("get_last_exclusive_window()", scan)
        self.assertIn("dialog->reparent(popup_parent);", scan)

    def test_popup_is_centered(self):
        scan = section("void EditorNode::_scan_external_changes() {",
                       "void EditorNode::_restore_disk_changed_dialog_parent() {")
        self.assertIn("dialog->popup_centered_ratio(0.3);", scan)

    def test_restore_checks_gui_base_alive(self):
        restore = section("void EditorNode::_restore_disk_changed_dialog_parent() {",
                          "void EditorNode::_resave_externally_modified_scenes(")
        self.assertIn("gui_base->is_inside_tree()", restore)
        self.assertIn("!dialog->is_visible()", restore)

    def test_restore_reparents_dialog_to_gui(self):
        restore = section("void EditorNode::_restore_disk_changed_dialog_parent() {",
                          "void EditorNode::_resave_externally_modified_scenes(")
        self.assertIn("dialog->reparent(gui_base);", restore)

    def test_constructor_no_longer_creates_dialog(self):
        ctor = section("EditorNode::EditorNode() {", "EditorNode::~EditorNode() {")
        self.assertNotIn("disk_changed = memnew(ConfirmationDialog)", ctor)

    def test_reload_and_ignore_paths_check_object_lifetime(self):
        self.assertGreaterEqual(CPP.count("ObjectDB::get_instance<ConfirmationDialog>(disk_changed)"), 4)

    def test_no_unchecked_dialog_hides(self):
        self.assertNotIn("disk_changed->hide();", CPP)

    def test_existing_translation_semantics_preserved(self):
        factory = section("ConfirmationDialog *EditorNode::_create_disk_changed_dialog() {",
                          "void EditorNode::_scan_external_changes() {")
        self.assertIn('dialog->set_title(TTRC("Files have been modified outside Godot"))', factory)
        self.assertIn('dialog->set_ok_button_text(TTRC("Reload from disk"))', factory)
        self.assertNotIn('dialog->set_title(TTR("Files have been modified outside Godot"))', factory)


if __name__ == "__main__":
    unittest.main()
