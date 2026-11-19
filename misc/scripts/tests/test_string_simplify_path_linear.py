"""Ensure path normalization uses one linear scan with legacy path behavior."""
import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]

class LinearPathContracts(unittest.TestCase):
    def test_single_buffer_no_component_vector(self):
        source=(ROOT/"core/string/ustring.cpp").read_text()
        code=source.split("String String::simplify_path() const {",1)[1].split("\nstatic int _humanize_digits(",1)[0]
        self.assertNotIn("Vector<String> dirs",code)
        self.assertNotIn('s.replace("//", "/")',code)
        self.assertNotIn("dirs.remove_at(",code)
        self.assertIn("normalized.resize_uninitialized(s.size());",code)
        self.assertIn("return drive + normalized;",code)

    def test_res_url_and_absolute_traversal_rules(self):
        source=(ROOT/"core/string/ustring.cpp").read_text()
        code=source.split("String String::simplify_path() const {",1)[1].split("\nstatic int _humanize_digits(",1)[0]
        self.assertIn('is_absolute_path() && !begins_with("res://")',code)
        self.assertIn("char32_t *fixed = dst_start;",code)
        self.assertIn("if (part_start > fixed)",code)
        self.assertIn("else if (absolute_path)",code)

if __name__=="__main__":
    unittest.main()
