"""Source-level regression checks for PopupMenu touch activation sounds, Godot #125407."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
SOURCE = (ROOT / "scene/gui/popup_menu.cpp").read_text(encoding="utf-8")
HEADER = (ROOT / "scene/gui/popup_menu.h").read_text(encoding="utf-8")
TOUCH_START = SOURCE.index("Ref<InputEventScreenTouch> touch = p_event;")
TOUCH_END = SOURCE.index("Ref<InputEventScreenDrag> drag = p_event;", TOUCH_START)
TOUCH = SOURCE[TOUCH_START:TOUCH_END]
HOVER_START = SOURCE.index("void PopupMenu::_mouse_over_update(")
HOVER = SOURCE[HOVER_START:SOURCE.index("void PopupMenu::_draw_items(", HOVER_START)]


class PopupMenuTouchSoundRegressions(unittest.TestCase):
    def test_mouse_hover_keeps_sound_enabled_by_default(self):
        self.assertIn("void _mouse_over_update(const Point2 &p_over, bool p_play_sound = true);", HEADER)

    def test_touch_press_avoids_hover_sounds_in_both_paths(self):
        self.assertEqual(TOUCH.count("_mouse_over_update(pos, false);"), 2)

    def test_touch_release_checks_pressed_item_identity(self):
        self.assertIn("over < 0 || over != touch_pressed_item", TOUCH)

    def test_separator_tap_cannot_activate(self):
        self.assertIn("if (items[over].separator) {", TOUCH)

    def test_touch_activation_has_enabled_and_disabled_sounds(self):
        self.assertIn("items[over].disabled ? theme_cache.item_activated_disabled_sound", TOUCH)
        self.assertIn("theme_cache.item_activated_sound", TOUCH)

    def test_disabled_item_returns_before_activation(self):
        self.assertIn("if (items[over].disabled) {", TOUCH)
        self.assertLess(TOUCH.index("if (items[over].disabled) {"),
                        TOUCH.index("activate_item(over);"))

    def test_submenu_remains_activated_on_touch(self):
        self.assertIn("_activate_submenu(over);", TOUCH)
        self.assertIn("activate_item(over);", TOUCH)

    def test_hover_sound_requires_explicit_permission(self):
        self.assertIn("if (p_play_sound && !items[over_index].disabled)", HOVER)

    def test_touch_press_resets_selection_before_reassignment(self):
        self.assertLess(TOUCH.index("touch_pressed_item = -1;"),
                        TOUCH.index("touch_pressed_item = over;"))


if __name__ == "__main__":
    unittest.main()
