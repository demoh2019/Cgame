#!/usr/bin/env python3
"""Regression checks for small upstream Godot backports.

These exercise the actual editor method in a standalone C++ harness and check
the GLES3 preprocessor branch under simulated compiler configurations.
They are not a substitute for a full editor/renderer build.
"""

from __future__ import annotations

import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from xml.etree import ElementTree

ROOT = Path(__file__).resolve().parents[3]
FIND_SOURCE = ROOT / "editor/script/find_in_files.cpp"
GLES_SOURCE = ROOT / "drivers/gles3/rasterizer_gles3.cpp"
TEXTURE_DOC = ROOT / "doc/classes/TextureRect.xml"


def extract_cpp_function(source: str, signature: str) -> str:
    start = source.index(signature)
    opening = source.index("{", start)
    depth = 0
    for i in range(opening, len(source)):
        if source[i] == "{":
            depth += 1
        elif source[i] == "}":
            depth -= 1
            if depth == 0:
                return source[start : i + 1]
    raise ValueError("C++ function closing brace not found")


class EditorFilterRegressionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.method = extract_cpp_function(
            FIND_SOURCE.read_text(encoding="utf-8"),
            "void FindInFilesSearchPanel::_update_finder()",
        )

    def test_filter_is_forwarded_exactly_once(self):
        self.assertEqual(self.method.count("finder->set_filter(get_filter());"), 1)

    def test_filter_is_applied_before_includes_and_excludes(self):
        method = self.method
        self.assertLess(method.index("finder->set_folder("), method.index("finder->set_filter("))
        self.assertLess(method.index("finder->set_filter("), method.index("finder->set_includes("))
        self.assertLess(method.index("finder->set_includes("), method.index("finder->set_excludes("))

    def test_rename_mode_is_guarded_before_updating(self):
        self.assertLess(self.method.index("if (finder->is_rename_mode())"), self.method.index("finder->set_filter("))
        self.assertIn("return;", self.method[: self.method.index("finder->set_filter(")])

    @unittest.skipUnless(shutil.which("c++"), "C++ compiler not installed")
    def test_actual_cpp_method_with_mock_editor_controls(self):
        prelude = r"""
#include <cassert>
#include <set>
#include <string>
#include <iostream>

struct String {
    std::string value;
    String(std::string p_value = "") : value(p_value) {}
    String strip_edges() const {
        size_t first = value.find_first_not_of(" \t\n");
        if (first == std::string::npos) return String("");
        size_t last = value.find_last_not_of(" \t\n");
        return String(value.substr(first, last - first + 1));
    }
};
struct LineEdit {
    String text;
    String get_text() const { return text; }
};
struct CheckBox {
    bool value = false;
    bool is_pressed() const { return value; }
};
struct Finder {
    bool rename = false, match_case = false, whole_words = false;
    String pattern, folder, includes, excludes;
    std::set<std::string> filters;
    bool is_rename_mode() const { return rename; }
    void set_search_text(const String &v) { pattern = v; }
    void set_match_case(bool v) { match_case = v; }
    void set_whole_words(bool v) { whole_words = v; }
    void set_folder(const String &v) { folder = v; }
    void set_filter(const std::set<std::string> &v) { filters = v; }
    void set_includes(const String &v) { includes = v; }
    void set_excludes(const String &v) { excludes = v; }
};
struct FindInFilesSearchPanel {
    Finder *finder;
    LineEdit *search_text_line_edit, *folder_line_edit, *includes_line_edit, *excludes_line_edit;
    CheckBox *match_case_checkbox, *whole_words_checkbox;
    std::set<std::string> selected_extensions;
    std::set<std::string> get_filter() const { return selected_extensions; }
    void _update_finder();
};
"""
        checks = r"""
#define CHECK(condition) do { \
    if (!(condition)) { std::cerr << "Failed: " #condition "\n"; return 1; } \
    ++checks; \
} while (0)
int main() {
    int checks = 0;
    Finder finder;
    LineEdit text, folder, includes, excludes;
    CheckBox match_case, whole_words;
    text.text = String("needle");
    folder.text = String("  res://assets  ");
    includes.text = String("*.gd");
    excludes.text = String("vendor/*");
    match_case.value = true;
    whole_words.value = true;
    FindInFilesSearchPanel panel{
        &finder, &text, &folder, &includes, &excludes,
        &match_case, &whole_words, {"gd", "tscn"}
    };
    panel._update_finder();
    CHECK(finder.filters == std::set<std::string>({"gd", "tscn"}));
    CHECK(finder.pattern.value == "needle");
    CHECK(finder.folder.value == "res://assets");
    CHECK(finder.includes.value == "*.gd");
    CHECK(finder.excludes.value == "vendor/*");
    CHECK(finder.match_case);
    CHECK(finder.whole_words);

    // Changing the UI selection must replace, not accumulate, old filters.
    panel.selected_extensions = {"gdshader"};
    match_case.value = false;
    whole_words.value = false;
    panel._update_finder();
    CHECK(finder.filters == std::set<std::string>({"gdshader"}));
    CHECK(!finder.match_case);
    CHECK(!finder.whole_words);

    // Empty selection is meaningful: search should not reuse stale filters.
    panel.selected_extensions.clear();
    panel._update_finder();
    CHECK(finder.filters.empty());

    // Rename mode must preserve the running finder's snapshot.
    panel.selected_extensions = {"cs"};
    finder.rename = true;
    text.text = String("another");
    panel._update_finder();
    CHECK(finder.filters.empty());
    CHECK(finder.pattern.value == "needle");

    finder.rename = false;
    panel._update_finder();
    CHECK(finder.filters == std::set<std::string>({"cs"}));
    CHECK(finder.pattern.value == "another");
    std::cout << checks << " editor assertions passed\n";
}
"""
        with tempfile.TemporaryDirectory() as temp:
            source = Path(temp) / "regression.cpp"
            binary = Path(temp) / "regression"
            source.write_text(prelude + "\n" + self.method + "\n" + checks, encoding="utf-8")
            compile_result = subprocess.run(
                [shutil.which("c++"), "-std=c++17", "-Wall", "-Wextra", "-Werror", str(source), "-o", str(binary)],
                capture_output=True, text=True, check=False,
            )
            self.assertEqual(compile_result.returncode, 0, compile_result.stderr)
            run_result = subprocess.run([str(binary)], capture_output=True, text=True, check=False)
            self.assertEqual(run_result.returncode, 0, run_result.stderr)
            self.assertIn("15 editor assertions passed", run_result.stdout)


class GLES3CompilerRegressionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source = GLES_SOURCE.read_text(encoding="utf-8")
        prefix = "#if defined(GLAD_ENABLED) || defined(EGL_ENABLED) || defined(ANDROID_ENABLED)"
        suffix = "#endif // GLAD_ENABLED || EGL_ENABLED || ANDROID_ENABLED"
        start = source.index(prefix)
        end = source.index(suffix, start) + len(suffix)
        cls.block = source[start:end]

    @unittest.skipUnless(shutil.which("c++"), "C++ preprocessor not installed")
    def test_strcpy_alias_only_for_msvc(self):
        probe = self.block + "\n#ifdef strcpy\nALIAS_ENABLED\n#else\nALIAS_DISABLED\n#endif\n"
        cases = [
            ((), False),
            (("GLAD_ENABLED",), False),
            (("GLAD_ENABLED", "_WIN32"), False),
            (("GLAD_ENABLED", "_WIN32", "__MINGW32__"), False),
            (("EGL_ENABLED", "_WIN32"), False),
            (("ANDROID_ENABLED",), False),
            (("_MSC_VER",), False),
            (("GLAD_ENABLED", "_MSC_VER"), True),
            (("GLAD_ENABLED", "_MSC_VER", "_WIN32"), True),
            (("EGL_ENABLED", "_MSC_VER"), True),
            (("ANDROID_ENABLED", "_MSC_VER"), True),
        ]
        for defines, expected in cases:
            with self.subTest(defines=defines):
                result = subprocess.run(
                    [shutil.which("c++"), "-E", "-P", "-x", "c++", "-", *("-D" + d for d in defines)],
                    input=probe, capture_output=True, text=True, check=False,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("ALIAS_ENABLED" if expected else "ALIAS_DISABLED", result.stdout)
                self.assertNotIn("ALIAS_DISABLED" if expected else "ALIAS_ENABLED", result.stdout)


class TextureRectDocsRegressionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = ElementTree.parse(TEXTURE_DOC).getroot()
        cls.description = (cls.root.findtext("description") or "").strip()

    def test_description_explains_default_minimum_size(self):
        self.assertIn("minimum size", self.description)
        self.assertIn("assigned [member texture]", self.description)

    def test_description_recommends_supported_expand_mode(self):
        self.assertIn("[constant EXPAND_IGNORE_SIZE]", self.description)
        self.assertIn("[member expand_mode]", self.description)
        self.assertIsNotNone(self.root.find(".//member[@name='expand_mode']"))

    def test_explanation_is_not_duplicated(self):
        self.assertEqual(self.description.count("minimum size of [TextureRect]"), 1)


if __name__ == "__main__":
    unittest.main()
