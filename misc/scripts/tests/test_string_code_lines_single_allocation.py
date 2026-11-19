"""Source and regression contracts for a single-allocation String::get_with_code_lines()."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
SRC = (ROOT / "core/string/ustring.cpp").read_text(encoding="utf-8")
NATIVE = (ROOT / "tests/core/string/test_string.cpp").read_text(encoding="utf-8")
BEGIN = SRC.index("String String::get_with_code_lines() const {")
END = SRC.index("int String::get_slice_count(", BEGIN)
FUNCTION = SRC[BEGIN:END]


class StringCodeLinesPerformanceTests(unittest.TestCase):
    def test_output_resizes_exactly_once(self):
        self.assertEqual(FUNCTION.count("result.resize_uninitialized("), 1)

    def test_no_intermediate_split_or_string_concat(self):
        self.assertNotIn('split("\\n")', FUNCTION)
        self.assertNotIn("vformat(", FUNCTION)
        self.assertNotIn("result +=", FUNCTION)

    def test_format_counts_trailing_empty_lines(self):
        self.assertIn("uint64_t line_count = 1;", FUNCTION)
        self.assertIn("pos <= source_length", FUNCTION)

    def test_preserves_four_column_minimum(self):
        self.assertIn("line_count * 7", FUNCTION)
        self.assertIn("for (int i = digits; i < 4; i++)", FUNCTION)

    def test_long_line_numbers_get_extra_characters(self):
        self.assertIn("threshold = 10000", FUNCTION)
        self.assertIn("result_length += line_count - threshold + 1;", FUNCTION)

    def test_copies_unicode_without_encoding_conversion(self):
        self.assertIn("memcpy(output + write_pos", FUNCTION)
        self.assertIn("sizeof(char32_t)", FUNCTION)

    def test_output_has_length_guard_and_terminator(self):
        self.assertIn("result_length > INT32_MAX", FUNCTION)
        self.assertIn("output[write_pos] = 0;", FUNCTION)

    def test_native_test_preserves_reference_format(self):
        self.assertIn("get_with_code_lines_reference", NATIVE)
        self.assertIn('String("x\\n").repeat(10001)', NATIVE)
        self.assertIn('String::utf8("Привет\\n🎮 Unicode")', NATIVE)


if __name__ == "__main__":
    unittest.main()
