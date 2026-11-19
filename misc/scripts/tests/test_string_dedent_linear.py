"""Regression source checks for String::dedent linear, single-allocation path."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]


class DedentLinearTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cpp = (ROOT / "core/string/ustring.cpp").read_text(encoding="utf-8")
        start = cpp.index("String String::dedent() const {")
        end = cpp.index("\n}\n", start)
        cls.body = cpp[start:end]
        cls.native = (ROOT / "tests/core/string/test_string.cpp").read_text(encoding="utf-8")

    def test_no_incremental_concatenation(self):
        self.assertNotIn("new_string +=", self.body)
        self.assertNotIn("substr(", self.body)

    def test_scans_first_meaningful_line(self):
        self.assertIn("c > 32", self.body)
        self.assertIn("indent_length = i - line_begin;", self.body)

    def test_strips_whitespace_only_lines(self):
        self.assertIn("if (first_text == p_end)", self.body)

    def test_maintains_prefix_mismatch(self):
        self.assertIn("read[copy_begin] == read[indent_begin + copy_begin - p_begin]", self.body)

    def test_cow_noop_fast_path(self):
        self.assertIn("if (!changed)", self.body)
        self.assertIn("return *this;", self.body)

    def test_output_size_computed_before_allocation(self):
        self.assertLess(self.body.index("result_length +="), self.body.index("resize_uninitialized("))

    def test_exactly_one_final_buffer_allocation(self):
        self.assertEqual(self.body.count("resize_uninitialized("), 1)

    def test_bulk_line_copy(self):
        self.assertIn("memcpy(write + written, read + copy_begin, copy_count * sizeof(char32_t));", self.body)

    def test_final_nul(self):
        self.assertIn("write[written] = 0;", self.body)

    def test_native_case_coverage(self):
        self.assertIn('dedent linear-time whitespace and Unicode', self.native)
        self.assertIn('dedent linear-time large multiline input', self.native)

    def test_native_cow_test(self):
        self.assertIn("unchanged.ptr() == original.ptr()", self.native)


if __name__ == "__main__":
    unittest.main()
