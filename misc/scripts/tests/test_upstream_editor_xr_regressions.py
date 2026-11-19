"""Source regression contracts for godotengine/godot #125557 and #125473.

These are structural tests, not XR hardware simulation or runtime Inspector tests.
The GitHub workflow separately compiles the Godot editor and runs native tests.
"""

from __future__ import annotations

from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
XR_CPP = ROOT / "modules/openxr/openxr_api.cpp"
XR_H = ROOT / "modules/openxr/openxr_api.h"
GD_CPP = ROOT / "modules/gdscript/gdscript.cpp"


def section(source: str, start: str, end: str) -> str:
    """Locate one exact source section, refusing to silently check the wrong one."""
    first = source.find(start)
    if first == -1:
        raise AssertionError("Source section not found: " + start)
    second = source.find(end, first + len(start))
    if second == -1:
        raise AssertionError("Section end not found: " + end)
    return source[first:second]


class SourceSectionHelperTests(unittest.TestCase):
    def test_extract_section(self):
        self.assertEqual(section("A [x] B [y] C", "[x]", "[y]"), "[x] B ")

    def test_missing_start_rejected(self):
        with self.assertRaises(AssertionError):
            section("[x] [y]", "[z]", "[y]")

    def test_missing_end_rejected(self):
        with self.assertRaises(AssertionError):
            section("[x] [y]", "[x]", "[z]")


class OpenXRLogRegressions(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cpp = XR_CPP.read_text(encoding="utf-8")
        cls.header = XR_H.read_text(encoding="utf-8")
        cls.helper = section(cls.cpp, "void OpenXRAPI::report_frame_loop_error(",
                             "String OpenXRAPI::get_swapchain_format_name(")
        cls.wait = section(cls.cpp, "XrResult result = xrWaitFrame(",
                           "if (frame_state.predictedDisplayPeriod >")
        cls.begin = section(cls.cpp, "XrResult result = xrBeginFrame(",
                            "// Reset this, we haven't found a viewport")
        cls.end = section(cls.cpp, "void OpenXRAPI::end_frame()", "void OpenXRAPI::")

    def test_helper_has_result_reference(self):
        self.assertIn("XrResult &r_last_error", self.helper)

    def test_helper_uses_verbose_for_repeat(self):
        self.assertRegex(self.helper, r"if\s*\(p_result\s*==\s*r_last_error\)\s*\{[^}]*print_verbose")

    def test_helper_returns_after_repeat(self):
        self.assertRegex(self.helper, r"if\s*\(p_result\s*==\s*r_last_error\)\s*\{[^}]*return;")

    def test_helper_updates_last_error(self):
        self.assertIn("r_last_error = p_result;", self.helper)

    def test_helper_logs_new_error(self):
        self.assertIn("print_error(", self.helper)

    def test_helper_does_not_print_line(self):
        self.assertNotIn("print_line(", self.helper)

    def test_wait_failure_uses_throttle(self):
        self.assertIn('report_frame_loop_error(last_wait_frame_error, result, "xrWaitFrame() was not successful")', self.wait)

    def test_wait_success_resets_error(self):
        self.assertIn("last_wait_frame_error = XR_SUCCESS;", self.wait)

    def test_wait_failure_does_not_reset_before_return(self):
        self.assertLess(self.wait.index("return false;"), self.wait.index("last_wait_frame_error = XR_SUCCESS;"))

    def test_begin_failure_uses_throttle(self):
        self.assertIn('report_frame_loop_error(render_state.last_begin_frame_error, result, "failed to begin frame")', self.begin)

    def test_begin_success_resets_error(self):
        self.assertIn("render_state.last_begin_frame_error = XR_SUCCESS;", self.begin)

    def test_begin_failure_does_not_reset_before_return(self):
        self.assertLess(self.begin.index("return;"), self.begin.index("render_state.last_begin_frame_error = XR_SUCCESS;"))

    def test_end_failure_paths_share_state(self):
        self.assertEqual(self.end.count("report_frame_loop_error(render_state.last_end_frame_error, result,"), 2)

    def test_end_success_paths_reset_state(self):
        self.assertEqual(self.end.count("render_state.last_end_frame_error = XR_SUCCESS;"), 2)

    def test_no_old_wait_spam(self):
        self.assertNotIn('print_line("OpenXR: xrWaitFrame() was not successful', self.cpp)

    def test_no_old_begin_spam(self):
        self.assertNotIn('print_line("OpenXR: failed to begin frame', self.cpp)

    def test_no_old_end_spam(self):
        self.assertNotIn('print_line("OpenXR: failed to end frame', self.cpp)

    def test_header_declares_helper(self):
        self.assertIn("void report_frame_loop_error(XrResult &r_last_error, XrResult p_result, const char *p_what);", self.header)

    def test_wait_error_is_initialized(self):
        self.assertIn("XrResult last_wait_frame_error = XR_SUCCESS;", self.header)

    def test_render_error_state_is_initialized(self):
        for member in ("last_begin_frame_error", "last_end_frame_error"):
            with self.subTest(member=member):
                self.assertIn("XrResult " + member + " = XR_SUCCESS;", self.header)


class GDScriptInspectorRegressions(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cpp = GD_CPP.read_text(encoding="utf-8")
        cls.reload = section(cls.cpp, "Error GDScript::reload(bool p_keep_state) {",
                             "ScriptLanguage *GDScript::get_language() const")
        cls.notify = section(cls.reload, "// Update the properties in the inspector.",
                             "#endif")

    def test_reload_updates_exports(self):
        self.assertIn("update_exports();", self.notify)

    def test_editor_only_notification(self):
        self.assertIn("if (Engine::get_singleton()->is_editor_hint())", self.notify)

    def test_keep_state_guard(self):
        self.assertRegex(self.notify, r"update_exports\(\);\s*if \(Engine::get_singleton\(\)->is_editor_hint\(\)\)")
        self.assertRegex(self.reload, r"if \(p_keep_state\) \{\s*// Update the properties in the inspector")

    def test_copy_owners_under_lock(self):
        self.assertIn("MutexLock lock(GDScriptLanguage::singleton->mutex);", self.notify)
        self.assertIn("for (SelfList<GDScriptInstance> *E = instances.first();", self.notify)
        self.assertIn("E = E->next()", self.notify)

    def test_owner_ids_are_snapshotted(self):
        self.assertIn("get_owner()->get_instance_id()", self.notify)

    def test_notifies_by_resolved_id(self):
        self.assertIn("ObjectDB::get_instance(id)", self.notify)

    def test_does_not_dereference_freed_owner(self):
        self.assertRegex(self.notify, r"if \(owner\) \{\s*owner->notify_property_list_changed\(\);")

    def test_notifications_happen_after_mutex_release(self):
        # No user callback / notification may fire while holding the script mutex.
        lock = self.notify.index("MutexLock lock(")
        close = self.notify.index("\n\t\t\t}\n", lock)
        emit = self.notify.index("owner->notify_property_list_changed();")
        self.assertLess(close, emit)
        self.assertNotIn("notify_property_list_changed();", self.notify[lock:close])

    def test_no_changes_to_reload_signature(self):
        self.assertIn("Error GDScript::reload(bool p_keep_state)", self.cpp)


if __name__ == "__main__":
    unittest.main()
