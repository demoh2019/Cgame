"""Production source regressions for Godot editor ResourcePicker #124656."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
SRC = (ROOT / "editor/inspector/editor_resource_picker.cpp").read_text(encoding="utf-8")
HDR = (ROOT / "editor/inspector/editor_resource_picker.h").read_text(encoding="utf-8")


def body(name):
    sig = "void EditorResourcePicker::" + name + "()"
    start = SRC.index(sig)
    end = SRC.index("\n}\n", start) + 2
    return SRC[start:end]


class ResourcePickerMinimalRefreshTests(unittest.TestCase):
    def test_declared_helper(self):
        self.assertIn("void _update_make_unique_button();", HDR)

    def test_calls_unique_updater_in_full_refresh(self):
        self.assertEqual(body("_update_resource").count("_update_make_unique_button();"), 1)

    def test_full_refresh_keeps_preview(self):
        self.assertIn("queue_edited_resource_preview(", body("_update_resource"))

    def test_unique_helper_does_not_queue_previews(self):
        self.assertNotIn("queue_edited_resource_preview(", body("_update_make_unique_button"))

    def test_unique_helper_does_not_modify_assign_button(self):
        self.assertNotIn("assign_button->", body("_update_make_unique_button"))

    def test_unique_helper_does_not_modify_quick_load_button(self):
        self.assertNotIn("quick_load_button->", body("_update_make_unique_button"))

    def test_unique_helper_handles_null_resources(self):
        helper = body("_update_make_unique_button")
        self.assertIn("if (edited_resource.is_null())", helper)
        self.assertIn("make_unique_button->set_visible(false);", helper)

    def test_unique_helper_recomputes_reference_count(self):
        helper = body("_update_make_unique_button")
        self.assertIn("get_resource_count(edited_resource)", helper)
        self.assertIn("num_of_copies > 1", helper)

    def test_unique_helper_retains_editability(self):
        self.assertIn("make_unique_button->set_disabled(", body("_update_make_unique_button"))

    def test_full_refresh_retains_other_buttons(self):
        full = body("_update_resource")
        self.assertIn("assign_button->set_disabled(!editable && edited_resource.is_null());", full)
        self.assertIn("quick_load_button->set_visible(editable && edited_resource.is_null());", full)

    def test_counter_signal_uses_lightweight_callback(self):
        self.assertIn('connect("resource_counter_changed", callable_mp(this, &EditorResourcePicker::_update_make_unique_button))', SRC)
        self.assertNotIn('connect("resource_counter_changed", callable_mp(this, &EditorResourcePicker::_update_resource))', SRC)

    def test_disconnect_matches_connect(self):
        section = SRC[SRC.index("case NOTIFICATION_EXIT_TREE:"):SRC.index("case NOTIFICATION_EXIT_TREE:") + 820]
        self.assertIn("Callable resource_counter_changed = callable_mp(this, &EditorResourcePicker::_update_make_unique_button);", section)
        self.assertIn('disconnect("resource_counter_changed", resource_counter_changed)', section)


if __name__ == "__main__":
    unittest.main()
