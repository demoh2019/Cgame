"""Source-level guardrails for allocation-free compound case conversion loops.

Native String behavior is exercised in tests/core/string/test_string.cpp.
"""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "core/string/ustring.cpp"
NATIVE_TESTS = ROOT / "tests/core/string/test_string.cpp"


def body_between(source, begin, end):
    return source.split(begin, 1)[1].split(end, 1)[0]


class CompoundCasePerformanceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = SOURCE.read_text(encoding="utf-8")

    def test_compound_normalizer_allocates_result_once(self):
        body = body_between(
            self.source, "String String::_separate_compound_words() const {",
            "enum class _CompoundWordCase",
        )
        self.assertIn("result.resize_uninitialized(len + separators + 1)", body)
        self.assertIn("char32_t *dst = result.ptrw()", body)
        self.assertNotIn("substr(", body)
        self.assertNotIn("new_string +=", body)
        self.assertNotIn("return new_string.to_lower()", body)

    def test_compound_boundaries_match_legacy_rules(self):
        body = body_between(
            self.source, "static _FORCE_INLINE_ bool _compound_word_boundary(",
            "String String::_separate_compound_words() const {",
        )
        for rule in (
            "(prev_lower && curr_upper)",
            "((prev_upper || prev_digit) && curr_upper && next_lower)",
            "(prev_digit && curr_lower && next_lower)",
            "((prev_upper || prev_lower) && curr_digit)",
        ):
            self.assertIn(rule, body)

    def test_unicode_lowercase_and_delimiters(self):
        body = body_between(
            self.source, "String String::_separate_compound_words() const {",
            "enum class _CompoundWordCase",
        )
        for expr in (
            "is_whitespace(ch)", "is_underscore(ch)", "is_hyphen(ch)",
            "String::char_lowercase(ch)",
        ):
            self.assertIn(expr, body)

    def test_formatter_never_creates_temporary_slices(self):
        body = body_between(
            self.source, "static String _convert_compound_words(",
            "String String::capitalize() const {",
        )
        for obsolete in ("get_slicec(", "get_slice_count(", "substr(", "push_back(", " += "):
            self.assertNotIn(obsolete, body)
        self.assertIn("result.resize_uninitialized(output_len + 1)", body)
        self.assertIn("String::char_uppercase(ch)", body)
        self.assertIn("String::char_lowercase(ch)", body)

    def test_all_three_apis_share_formatter(self):
        for api, style in (
            ("capitalize", "CAPITALIZE"),
            ("to_camel_case", "CAMEL"),
            ("to_pascal_case", "PASCAL"),
        ):
            fragment = body_between(
                self.source, f"String String::{api}() const {{",
                "\n}",
            )
            self.assertIn(f"_CompoundWordCase::{style}", fragment)

    def test_native_equivalence_and_stress_registered(self):
        native = NATIVE_TESTS.read_text(encoding="utf-8")
        self.assertIn("compound word case conversion linear-path regression", native)
        self.assertIn("String(\"a_\").repeat(256)", native)
        self.assertIn("reference_pascal", native)


if __name__ == "__main__":
    unittest.main()
