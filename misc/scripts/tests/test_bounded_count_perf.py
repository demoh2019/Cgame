"""Guard bounded String::count/countn against accidental range copies."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "core/string/ustring.cpp"
TEST = ROOT / "tests/core/string/test_string.cpp"


class BoundedCountContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        src = SOURCE.read_text(encoding="utf-8")
        cls.count_impl = src.split(
            "int String::_count(const String &p_string,", 1
        )[1].split("int String::count(const String &p_string,", 1)[0]

    def test_no_substring_copies_or_temporary_string(self):
        self.assertNotIn("substr(", self.count_impl)
        self.assertNotIn("String str;", self.count_impl)
        self.assertIn("Span<const char32_t> range", self.count_impl)

    def test_window_clamped_before_pointer_arithmetic(self):
        self.assertEqual(self.count_impl.count("p_to == 0 ? len : MIN(p_to, len)"), 2)
        self.assertEqual(self.count_impl.count("p_from > end - needle_len"), 2)

    def test_nonoverlapping_scanning_and_unicode(self):
        self.assertEqual(self.count_impl.count("i += needle_len"), 2)
        self.assertEqual(self.count_impl.count("from = int(found) + needle_len"), 2)
        self.assertEqual(self.count_impl.count("strings_equal_lower("), 2)

    def test_signed_char_compatibility(self):
        self.assertIn("static_cast<char32_t>(*p_string)", self.count_impl)
        self.assertIn("Span((const unsigned char *)p_string, needle_len)", self.count_impl)

    def test_native_equivalence_oracle_and_large_window(self):
        tests = TEST.read_text(encoding="utf-8")
        self.assertIn("bounded count without substring allocations", tests)
        self.assertIn("legacy_cstring_count", tests)
        self.assertIn("legacy_string_count", tests)
        self.assertIn('String("a").repeat(4096)', tests)


if __name__ == "__main__":
    unittest.main()
