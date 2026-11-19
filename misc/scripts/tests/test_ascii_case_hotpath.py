"""Static regression contracts for fast String Unicode/ASCII case handling.

Native engine tests additionally cover actual conversions. Source contracts are
not performance measurements; compile the standalone benchmark for timings.
"""

from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
HEADER = ROOT / "core/string/ustring.h"
SOURCE = ROOT / "core/string/ustring.cpp"
BENCH = ROOT / "misc/scripts/benchmarks/benchmark_unicode_ascii.cpp"


class AsciiCaseSourceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.header = HEADER.read_text(encoding="utf-8")
        cls.source = SOURCE.read_text(encoding="utf-8")
        cls.bench = BENCH.read_text(encoding="utf-8")

    def test_lower_scalar_inlined(self):
        self.assertIn("static _FORCE_INLINE_ char32_t char_lowercase(char32_t p_char)", self.header)

    def test_upper_scalar_inlined(self):
        self.assertIn("static _FORCE_INLINE_ char32_t char_uppercase(char32_t p_char)", self.header)

    def test_lower_ascii_guard(self):
        self.assertRegex(self.header, r"char_lowercase\(char32_t p_char\)\s*\{\s*if \(p_char < 128\)")

    def test_upper_ascii_guard(self):
        self.assertRegex(self.header, r"char_uppercase\(char32_t p_char\)\s*\{\s*if \(p_char < 128\)")

    def test_lower_predicate(self):
        self.assertIn("is_ascii_upper_case(p_char)", self.header)

    def test_upper_predicate(self):
        self.assertIn("is_ascii_lower_case(p_char)", self.header)

    def test_lower_unicode_fallback(self):
        self.assertIn("return _char_lowercase_table(p_char);", self.header)
        self.assertIn("return _find_lower(p_char);", self.source)

    def test_upper_unicode_fallback(self):
        self.assertIn("return _char_uppercase_table(p_char);", self.header)
        self.assertIn("return _find_upper(p_char);", self.source)

    def test_lower_non_ascii_helper_declared(self):
        self.assertIn("static char32_t _char_lowercase_table(char32_t p_char);", self.header)

    def test_upper_non_ascii_helper_declared(self):
        self.assertIn("static char32_t _char_uppercase_table(char32_t p_char);", self.header)

    def test_ascii_string_lower_fastpath(self):
        lower = self.source.split("String String::to_lower() const {", 1)[1].split("String String::num(", 1)[0]
        self.assertIn("ch < 128", lower)
        self.assertIn("is_ascii_upper_case(ch)", lower)
        self.assertIn("_find_lower(ch)", lower)

    def test_ascii_string_upper_fastpath(self):
        upper = self.source.split("String String::to_upper() const {", 1)[1].split("String String::to_lower() const {", 1)[0]
        self.assertIn("ch < 128", upper)
        self.assertIn("is_ascii_lower_case(ch)", upper)
        self.assertIn("_find_upper(ch)", upper)

    def test_no_behavior_change_to_empty_string(self):
        for name in ("to_lower", "to_upper"):
            body = self.source.split(f"String String::{name}() const {{", 1)[1].split("return ", 1)[0]
            self.assertIn("if (is_empty())", body)

    def test_actual_table_used_by_benchmark(self):
        self.assertIn('#include "core/string/ucaps.h"', self.bench)
        self.assertIn("_find_lower(", self.bench)
        self.assertIn("_find_upper(", self.bench)

    def test_benchmark_exhaustive_ascii_equivalence(self):
        self.assertIn("codepoint < 128", self.bench)
        self.assertIn("original_lower(codepoint) != fast_lower(codepoint)", self.bench)
        self.assertIn("original_upper(codepoint) != fast_upper(codepoint)", self.bench)

    def test_benchmark_unicode_equivalence(self):
        self.assertIn("i < UTL_LEN", self.bench)
        self.assertIn("i < LTU_LEN", self.bench)

    def test_benchmark_checksums_verified(self):
        self.assertIn("old_sum != new_sum", self.bench)

    def test_benchmark_is_non_blocking(self):
        self.assertNotIn("speedup <", self.bench)
        self.assertNotIn("speedup >", self.bench)


if __name__ == "__main__":
    unittest.main()
