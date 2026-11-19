"""Verify that the production wildcard matcher preserves semantics and avoids recursion.

Builds a tiny standalone executable containing the exact matcher body extracted
from core/string/ustring.cpp and Godot's actual Unicode uppercase tables.
"""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "core/string/ustring.cpp"


def production_matcher():
    source = SOURCE.read_text(encoding="utf-8")
    start = source.index("static bool _wildcard_match(")
    end = source.index("\nbool String::match(", start)
    return source[start:end]


class WildcardHotPathTests(unittest.TestCase):
    def test_constant_extra_memory_and_unicode_fallback(self):
        match = production_matcher()
        self.assertNotIn("_wildcard_match(", match[match.index("{") + 1 :])
        self.assertIn("star_pattern = ++p_pattern", match)
        self.assertIn("p_string = ++star_string", match)
        self.assertIn("String::char_uppercase(", match)
        self.assertIn("*p_string != '.'", match)

    def test_real_production_matcher_equivalence_and_benchmark(self):
        matcher = production_matcher()
        code = r"""
#include "core/string/ucaps.h"
#include <chrono>
#include <cstdio>
#include <string>
#include <vector>
#include <cstdlib>

struct String {
    static char32_t char_uppercase(char32_t ch) {
        return ch < 128 ? (ch >= 'a' && ch <= 'z' ? ch - ('a' - 'A') : ch) : _find_upper(ch);
    }
};
""" + matcher + r"""
// The previous production algorithm, retained here only for small oracle inputs.
static bool reference(const char32_t *pat, const char32_t *str, bool cs) {
    switch (*pat) {
        case '\0': return !*str;
        case '*': return reference(pat + 1, str, cs) || (*str && reference(pat, str + 1, cs));
        case '?': return *str && *str != '.' && reference(pat + 1, str + 1, cs);
        default: return (cs ? *str == *pat : _find_upper(*str) == _find_upper(*pat)) &&
                       reference(pat + 1, str + 1, cs);
    }
}

static void generate(std::vector<std::u32string> &out, const std::u32string &current,
                     const std::u32string &alphabet, int remaining) {
    out.push_back(current);
    if (remaining <= 0) return;
    for (char32_t ch : alphabet) generate(out, current + ch, alphabet, remaining - 1);
}

int main() {
    std::vector<std::u32string> texts, patterns;
    generate(texts, U"", U"aAb.", 4);
    generate(patterns, U"", U"ab.?*", 4);
    size_t checked = 0;
    for (const auto &s : texts) {
        if (s.empty()) continue; // String::match() rejects empty inputs.
        for (const auto &p : patterns) {
            if (p.empty()) continue;
            for (bool case_sensitive : {false, true}) {
                if (reference(p.c_str(), s.c_str(), case_sensitive) !=
                        _wildcard_match(p.c_str(), s.c_str(), case_sensitive)) {
                    std::fprintf(stderr, "wildcard mismatch at case %zu\n", checked);
                    return 1;
                }
                ++checked;
            }
        }
    }
    const std::u32string unicode = U"ÄΩЯ.txt";
    if (!_wildcard_match(U"*ä?я.TXT", unicode.c_str(), false) ||
            _wildcard_match(U"*ä?я.TXT", unicode.c_str(), true)) return 2;

    std::u32string text(30, U'a'), pat;
    for (int i = 0; i < 6; ++i) pat += U"*a";
    pat += U"b";
    const auto t0 = std::chrono::steady_clock::now();
    const bool old_result = reference(pat.c_str(), text.c_str(), true);
    const auto t1 = std::chrono::steady_clock::now();
    const bool new_result = _wildcard_match(pat.c_str(), text.c_str(), true);
    const auto t2 = std::chrono::steady_clock::now();
    if (old_result || new_result) return 3;
    const double before_us = std::chrono::duration<double, std::micro>(t1 - t0).count();
    const double after_us = std::chrono::duration<double, std::micro>(t2 - t1).count();
    std::printf("Matched oracle cases: %zu; pathological baseline: %.3f us; iterative: %.3f us\n",
                checked, before_us, after_us);

    std::u32string big_text(128, U'a'), big_pat;
    for (int i = 0; i < 24; ++i) big_pat += U"*a";
    big_pat += U"b";
    if (_wildcard_match(big_pat.c_str(), big_text.c_str(), true)) return 4;
    return 0;
}
"""
        compiler = os.environ.get("CXX") or shutil.which("c++")
        self.assertTrue(compiler, "A C++17 compiler is required for this test")
        with tempfile.TemporaryDirectory() as temp:
            source = Path(temp) / "wildcard.cpp"
            binary = Path(temp) / "wildcard"
            source.write_text(code, encoding="utf-8")
            compile_result = subprocess.run(
                [compiler, "-std=c++17", "-O2", "-Wall", "-Wextra", "-Werror", "-I.",
                 str(source), "-o", str(binary)],
                cwd=ROOT, capture_output=True, text=True, check=False, timeout=60,
            )
            self.assertEqual(compile_result.returncode, 0, compile_result.stderr)
            test_result = subprocess.run(
                [str(binary)], cwd=ROOT, capture_output=True, text=True,
                check=False, timeout=20,
            )
            self.assertEqual(test_result.returncode, 0, test_result.stderr)
            print(test_result.stdout.strip())


if __name__ == "__main__":
    unittest.main()
