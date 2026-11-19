"""Guard O(1) COW shared-buffer comparisons and the fixed != boolean condition."""
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[3]

class SharedBufferEquality(unittest.TestCase):
    def test_vector_copy_equality_shortcut(self):
        code=(ROOT/"core/templates/vector.h").read_text()
        self.assertIn("return _cowdata.ptr() == p_arr._cowdata.ptr() || span() == p_arr.span();", code)
        self.assertIn("return _cowdata.ptr() != p_arr._cowdata.ptr() && span() != p_arr.span();", code)
        self.assertNotIn("return _cowdata.ptr() == p_arr._cowdata.ptr() || span() != p_arr.span();", code)

    def test_string_copy_equality_and_case_compare_shortcuts(self):
        code=(ROOT/"core/string/ustring.cpp").read_text()
        self.assertIn("return _cowdata.ptr() == p_str._cowdata.ptr() || span() == p_str.span();", code)
        self.assertGreaterEqual(code.count("if (unlikely(p_str.ptr() == ptr()))"), 2)

if __name__=="__main__":
    unittest.main()
