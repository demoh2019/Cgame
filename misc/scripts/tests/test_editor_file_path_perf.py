"""Compile production editor file-path helpers against C++ test doubles.

Validates fast resource-path and case-insensitive span comparison introduced by
Godot upstream #124138. A full editor integration run remains necessary.
"""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "editor/file_system/editor_file_system.cpp"


def extract(src, signature):
    start = src.index(signature)
    start_brace = src.index("{", start)
    depth = 0
    for i in range(start_brace, len(src)):
        if src[i] == "{":
            depth += 1
        elif src[i] == "}":
            depth -= 1
            if depth == 0:
                return src[start:i + 1]
    raise AssertionError("Unbalanced production helper: " + signature)


class FilePathPerformanceContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = SOURCE.read_text(encoding="utf-8")
        cls.compare = extract(cls.source, "static bool _span_equals(")
        cls.simple = extract(cls.source, "static bool _is_simple_res_path(")
        cls.find = extract(cls.source, "bool EditorFileSystem::_find_file(")

    def test_simple_res_path_preserves_absolute_resource_prefix(self):
        self.assertIn('int seg_start = 6;', self.simple)
        self.assertIn("return len == 6 ||", self.simple)

    def test_rejects_path_traversal_and_duplicate_separators(self):
        self.assertIn("seg_len == 0 && i < len", self.simple)
        self.assertIn("seg_len == 1", self.simple)
        self.assertIn("seg_len == 2", self.simple)

    def test_case_insensitive_compare_keeps_equal_size_check(self):
        self.assertIn("if (p_a.size() != p_b.size())", self.compare)

    def test_case_insensitive_compare_avoids_allocating_lowercase_strings(self):
        self.assertIn("String::char_lowercase(a[i])", self.compare)
        self.assertIn("String::char_lowercase(b[i])", self.compare)
        self.assertNotIn(".to_lower()", self.compare)

    def test_fast_lookup_bypasses_costly_localization(self):
        self.assertIn("!_is_simple_res_path(f)", self.find)
        self.assertIn("ProjectSettings::get_singleton()->localize_path(p_file)", self.find)

    def test_fast_lookup_avoids_diraccess_creation(self):
        self.assertNotIn("DirAccess::create(DirAccess::ACCESS_FILESYSTEM)", self.find)

    def test_compile_actual_helpers_for_safe_and_unsafe_paths(self):
        cxx = shutil.which(os.environ.get("CXX", "g++"))
        if not cxx:
            self.skipTest("C++ compiler unavailable")
        prologue = r'''
#include <string>
#include <cstdint>
#include <cassert>
#include <iostream>
using uint64_t = std::uint64_t;
template<typename T> struct Span {
    const T *data;
    std::size_t count;
    Span(const T *p, std::size_t n) : data(p), count(n) {}
    std::size_t size() const { return count; }
    const T *ptr() const { return data; }
    bool operator==(const Span &other) const {
        if (count != other.count) return false;
        for (std::size_t i = 0; i < count; i++) {
            if (data[i] != other.data[i]) return false;
        }
        return true;
    }
};
struct String {
    std::u32string value;
    String(const char *s) {
        for (; *s; ++s) value.push_back(static_cast<unsigned char>(*s));
    }
    const char32_t *ptr() const { return value.c_str(); }
    int length() const { return value.size(); }
    static char32_t char_lowercase(char32_t c) {
        return c >= 'A' && c <= 'Z' ? c + ('a' - 'A') : c;
    }
};
'''
        epilogue = r'''
int main() {
    const std::pair<const char *, bool> paths[] = {
        {"res://", true},
        {"res://folder/scene.tscn", true},
        {"res://folder/.hidden", true},
        {"res://a//b", false},
        {"res://a/./b", false},
        {"res://a/../b", false},
        {"res://a/b/", false},
        {"res:///a", false},
        {"res://a\\b", false},
        {"res://assets/icon.png", true},
    };
    for (auto item : paths) {
        if (_is_simple_res_path(String(item.first)) != item.second) return 1;
    }
    const char32_t a[] = U"SomeFile.TSCN";
    const char32_t b[] = U"somefile.tscn";
    const char32_t c[] = U"unrelated.tscn";
    if (!_span_equals(Span<char32_t>(a, 13), Span<char32_t>(b, 13), false)) return 2;
    if (_span_equals(Span<char32_t>(a, 13), Span<char32_t>(b, 13), true)) return 3;
    if (_span_equals(Span<char32_t>(a, 13), Span<char32_t>(c, 14), false)) return 4;
    return 0;
}
'''
        with tempfile.TemporaryDirectory() as temporary:
            cpp = Path(temporary) / "path_perf.cpp"
            exe = Path(temporary) / "path_perf"
            cpp.write_text(prologue + "\n" + self.compare + "\n" + self.simple + "\n" + epilogue,
                           encoding="utf-8")
            build = subprocess.run([cxx, "-std=c++17", "-O2", str(cpp), "-o", str(exe)],
                                   capture_output=True, text=True, check=False, timeout=45)
            self.assertEqual(build.returncode, 0, build.stderr)
            result = subprocess.run([str(exe)], capture_output=True, text=True,
                                    check=False, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
