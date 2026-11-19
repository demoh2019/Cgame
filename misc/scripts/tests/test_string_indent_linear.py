"""Source-contract checks for the linear-time String::indent implementation.

These structural checks complement, but cannot replace, native engine tests.
"""
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[3]
SOURCE = ROOT / "core/string/ustring.cpp"
NATIVE = ROOT / "tests/core/string/test_string.cpp"


class IndentFastPathTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source = SOURCE.read_text(encoding="utf-8")
        start = source.index("String String::indent(")
        end = source.index("\n}\n", start)
        cls.method = source[start : end + 3]
        cls.native = NATIVE.read_text(encoding="utf-8")

    def test_cow_fast_return_for_empty_inputs(self):
        self.assertIn("if (is_empty() || p_prefix.is_empty())", self.method)
        self.assertIn("return *this;", self.method)

    def test_counts_only_nonempty_lines(self):
        self.assertIn("if (at_line_start && c != '\\n')", self.method)
        self.assertIn("nonempty_lines++;", self.method)

    def test_handles_only_empty_lines_without_allocation(self):
        self.assertIn("if (nonempty_lines == 0)", self.method)

    def test_overflow_guard_before_allocation(self):
        self.assertIn("int64_t result_length", self.method)
        self.assertLess(self.method.index("ERR_FAIL_COND_V_MSG(result_length"), self.method.index("resize_uninitialized("))

    def test_one_allocation(self):
        self.assertEqual(self.method.count("resize_uninitialized("), 1)

    def test_no_per_line_substring(self):
        self.assertNotIn("substr(", self.method)
        self.assertNotIn("new_string +=", self.method)

    def test_bulk_prefix_copy(self):
        self.assertIn("memcpy(write + written, prefix, prefix_length * sizeof(char32_t));", self.method)

    def test_nul_termination(self):
        self.assertIn("write[written] = 0;", self.method)

    def test_native_exhaustive_patterns(self):
        self.assertIn('[String] indent linear-time empty lines and Unicode', self.native)
        self.assertIn('[String] indent linear-time large multiline input', self.native)

    def test_native_cow_coverage(self):
        self.assertIn("same.ptr() == original.ptr()", self.native)


if __name__ == "__main__":
    unittest.main()
