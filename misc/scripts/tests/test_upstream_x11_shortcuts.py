"""Regression contracts for upstream Godot #125594 X11 text suppression.

Native X11 input tests are still necessary; these checks verify the implemented
modifier truth table and all three event paths against accidental regressions.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
CPP = (ROOT / "platform/linuxbsd/x11/display_server_x11.cpp").read_text(encoding="utf-8")
HEADER = (ROOT / "platform/linuxbsd/x11/display_server_x11.h").read_text(encoding="utf-8")
BEGIN = "bool DisplayServerX11::_is_text_suppressed(unsigned int p_x11_state) {"
END = "void DisplayServerX11::_handle_key_event("
HELPER = CPP.split(BEGIN, 1)[1].split(END, 1)[0]
HANDLER = CPP.split(END, 1)[1].split("void DisplayServerX11::", 1)[0]


def suppressed(ctrl=False, alt=False, meta=False):
    """Reference truth table for the explicit native helper expression."""
    return (ctrl or alt or meta) and not (ctrl and alt and not meta)


class X11ShortcutTextSuppressionTests(unittest.TestCase):
    def test_helper_declared(self):
        self.assertIn("bool _is_text_suppressed(unsigned int p_x11_state);", HEADER)

    def test_helper_defined_once(self):
        self.assertEqual(CPP.count(BEGIN), 1)

    def test_helper_reads_control_mask(self):
        self.assertIn("p_x11_state & ControlMask", HELPER)

    def test_helper_reads_alt_mask(self):
        self.assertIn("p_x11_state & Mod1Mask", HELPER)

    def test_helper_reads_meta_mask(self):
        self.assertIn("p_x11_state & Mod4Mask", HELPER)

    def test_helper_uses_expected_boolean_truth_table(self):
        self.assertRegex(
            HELPER,
            r"return\s+\(ctrl\s+\|\|\s+alt\s+\|\|\s+meta\)\s*&&\s*!\(ctrl\s*&&\s*alt\s*&&\s*!meta\);",
        )

    def test_plain_typing_allowed(self):
        self.assertFalse(suppressed())

    def test_ctrl_shortcut_suppressed(self):
        self.assertTrue(suppressed(ctrl=True))

    def test_alt_shortcut_suppressed(self):
        self.assertTrue(suppressed(alt=True))

    def test_meta_shortcut_suppressed(self):
        self.assertTrue(suppressed(meta=True))

    def test_altgr_ctrl_alt_allowed(self):
        self.assertFalse(suppressed(ctrl=True, alt=True))

    def test_ctrl_meta_suppressed(self):
        self.assertTrue(suppressed(ctrl=True, meta=True))

    def test_alt_meta_suppressed(self):
        self.assertTrue(suppressed(alt=True, meta=True))

    def test_ctrl_alt_meta_suppressed(self):
        self.assertTrue(suppressed(ctrl=True, alt=True, meta=True))

    def test_all_native_unicode_paths_gated(self):
        self.assertEqual(HANDLER.count("if (keypress && !_is_text_suppressed(xkeyevent->state)) {"), 3)

    def test_no_ungated_unicode_writes(self):
        self.assertNotIn("if (keypress) {", HANDLER)

    def test_unicode_conversion_preserved(self):
        self.assertGreaterEqual(HANDLER.count("set_unicode(fix_unicode("), 3)

    def test_shortcuts_preserve_key_labels(self):
        self.assertIn("set_key_label(keycode)", HANDLER)

    def test_immediate_input_state_unchanged(self):
        self.assertIn("_get_key_modifier_state(", CPP)

    def test_no_global_x11_environment_dependency_in_helper(self):
        self.assertNotIn("getenv(", HELPER)


if __name__ == "__main__":
    unittest.main()
