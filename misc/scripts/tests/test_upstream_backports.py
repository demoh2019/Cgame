"""Focused regression contracts for three small Godot upstream backports.

Run with:
  python3 -m unittest discover -s misc/scripts/tests -p test_upstream_backports.py -v

These fast tests check compiler preprocessing and source-level integration.
They DO NOT replace compiling the engine or exercising GUI/platform behavior.
"""

from __future__ import annotations

import shutil
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]


def read_source(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def method_body(source: str, signature: str) -> str:
    """Extract one function body, respecting nested braces."""
    offset = source.index(signature)
    start = source.index("{", offset)
    depth = 0
    for index in range(start, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[start + 1 : index]
    raise AssertionError(f"Unbalanced braces after {signature}")


class GLES3MSVCGuardTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        src = read_source("drivers/gles3/rasterizer_gles3.cpp")
        begin = src.index("#if defined(GLAD_ENABLED) || defined(EGL_ENABLED) || defined(ANDROID_ENABLED)")
        end_marker = "#endif // GLAD_ENABLED || EGL_ENABLED || ANDROID_ENABLED"
        end = src.index(end_marker, begin) + len(end_marker)
        cls.guard_source = src[begin:end]

    def preprocess_call(self, defines: tuple[str, ...]) -> str:
        cc = shutil.which("cc")
        if cc is None:
            self.skipTest("No C preprocessor installed")
        translation_unit = self.guard_source + "\nvoid probe(void) { strcpy(dst, src); }\n"
        proc = subprocess.run(
            [cc, "-E", "-P", "-x", "c", *(f"-D{symbol}" for symbol in defines), "-"],
            input=translation_unit,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        return proc.stdout

    def test_mingw_does_not_rewrite_strcpy(self):
        for defines in (
            ("_WIN32", "GLAD_ENABLED"),
            ("_WIN32", "EGL_ENABLED"),
            ("_WIN32", "ANDROID_ENABLED"),
        ):
            with self.subTest(defines=defines):
                output = self.preprocess_call(defines)
                self.assertIn("strcpy(dst, src)", output)
                self.assertNotIn("strcpy_s(dst, src)", output)

    def test_msvc_rewrites_strcpy_only_inside_gles3_guard(self):
        for backend in ("GLAD_ENABLED", "EGL_ENABLED", "ANDROID_ENABLED"):
            with self.subTest(backend=backend):
                output = self.preprocess_call(("_MSC_VER", "_WIN32", backend))
                self.assertIn("strcpy_s(dst, src)", output)

    def test_msvc_define_without_gles3_backend_does_not_rewrite(self):
        output = self.preprocess_call(("_MSC_VER", "_WIN32"))
        self.assertIn("strcpy(dst, src)", output)

    def test_non_windows_does_not_rewrite(self):
        output = self.preprocess_call(("GLAD_ENABLED",))
        self.assertIn("strcpy(dst, src)", output)


class MacOSWindowFailureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.display = read_source("platform/macos/display_server_macos.mm")
        cls.gl_header = read_source("platform/macos/gl_manager_macos_legacy.h")

    def test_failed_window_creation_sets_error(self):
        pos = self.display.index("WindowID main_window = _create_window(")
        block = self.display[pos : pos + 500]
        self.assertRegex(
            block,
            r"if \(main_window == DisplayServerEnums::INVALID_WINDOW_ID\)\s*\{\s*"
            r"r_error = ERR_CANT_CREATE;\s*ERR_FAIL_MSG",
        )

    def test_window_error_is_reported_before_return(self):
        pos = self.display.index("WindowID main_window = _create_window(")
        block = self.display[pos : pos + 500]
        self.assertLess(block.index("r_error = ERR_CANT_CREATE;"), block.index("ERR_FAIL_MSG"))

    def test_invalid_window_does_not_use_old_early_return(self):
        pos = self.display.index("WindowID main_window = _create_window(")
        block = self.display[pos : pos + 500]
        self.assertNotIn("ERR_FAIL_COND(main_window == DisplayServerEnums::INVALID_WINDOW_ID)", block)

    def test_clang_warning_push_is_balanced_by_pop(self):
        self.assertEqual(self.gl_header.count("GODOT_CLANG_WARNING_PUSH_AND_IGNORE"), 1)
        self.assertEqual(self.gl_header.count("GODOT_CLANG_WARNING_POP"), 1)
        self.assertLess(
            self.gl_header.index("GODOT_CLANG_WARNING_PUSH_AND_IGNORE"),
            self.gl_header.index("GODOT_CLANG_WARNING_POP"),
        )


class FindInFilesExtensionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cpp = read_source("editor/script/find_in_files.cpp")
        cls.update = method_body(cls.cpp, "void FindInFilesSearchPanel::_update_finder()")

    def test_update_propagates_selected_file_extensions(self):
        self.assertIn("finder->set_filter(get_filter());", self.update)

    def test_filter_is_copied_once(self):
        self.assertEqual(self.update.count("finder->set_filter(get_filter());"), 1)

    def test_filter_is_applied_before_include_exclude_wildcards(self):
        self.assertLess(self.update.index("finder->set_filter(get_filter());"), self.update.index("finder->set_includes("))
        self.assertLess(self.update.index("finder->set_filter(get_filter());"), self.update.index("finder->set_excludes("))

    def test_rename_mode_remains_untouched(self):
        self.assertRegex(self.update, r"if \(finder->is_rename_mode\(\)\)\s*\{[^{}]*return;\s*\}")
        self.assertLess(self.update.index("return;"), self.update.index("finder->set_filter(get_filter());"))

    def test_find_action_refreshes_finder_first(self):
        body = method_body(self.cpp, "void FindInFilesSearchPanel::_emit_find_requested()")
        self.assertLess(body.index("_update_finder();"), body.index('emit_signal("find_requested");'))

    def test_search_modification_refreshes_finder(self):
        body = method_body(self.cpp, "void FindInFilesSearchPanel::_on_search_modified()")
        self.assertIn("_update_finder();", body)

    def test_selected_checkboxes_form_extension_filter(self):
        body = method_body(self.cpp, "HashSet<String> FindInFilesSearchPanel::get_filter() const")
        self.assertRegex(body, r"if \(cb->is_pressed\(\)\)\s*\{\s*filters.insert\(cb->get_text\(\)\);")

    def test_toggle_triggers_refresh(self):
        body = method_body(self.cpp, "void FindInFilesSearchPanel::_on_filter_toggled(")
        self.assertIn("_on_search_modified();", body)

    def test_empty_extension_set_stops_search(self):
        body = method_body(self.cpp, "void FindInFilesSearch::start()")
        self.assertRegex(body, r"if \(extension_filter.is_empty\(\)\)\s*\{[^{}]*finished[^{}]*return;")

    def test_search_copy_preserves_extensions(self):
        body = method_body(self.cpp, "void FindInFilesSearch::copy_from(")
        self.assertIn("extension_filter = p_other->extension_filter;", body)


if __name__ == "__main__":
    unittest.main()
