#!/usr/bin/env python3
"""Check TextEdit bulk wrapping does not rescan or relock TextParagraph per range."""
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[3]


def code(filename):
    return (ROOT/filename).read_text(encoding="utf-8")


class BulkLineRangeContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        paragraph=code("scene/resources/text_paragraph.cpp")
        text_edit=code("scene/gui/text_edit.cpp")
        cls.bulk=paragraph.split("Vector<Vector2i> TextParagraph::get_line_ranges() const {",1)[1].split("\n}",1)[0]
        cls.get=text_edit.split("Vector<Vector2i> TextEdit::Text::get_line_wrap_ranges(int p_line) const {",1)[1].split("\n}",1)[0]
        cls.single=paragraph.split("Vector2i TextParagraph::get_line_range(int p_line) const {",1)[1].split("\n}",1)[0]

    def test_bulk_operation_single_shaping_and_lock(self):
        self.assertEqual(self.bulk.count("_THREAD_SAFE_METHOD_"),1)
        self.assertEqual(self.bulk.count("_shape_lines();"),1)
        self.assertEqual(self.bulk.count("shaped_text_get_range("),1)
        self.assertIn("ret.resize(lines_rid.size());",self.bulk)
        self.assertIn("TS->shaped_text_get_range(lines_rid[i])",self.bulk)

    def test_text_edit_delegates_once_and_keeps_bounds(self):
        self.assertIn("ERR_FAIL_INDEX_V(p_line, (int)text.size(),",self.get)
        self.assertIn("text[p_line].data_buf->get_line_ranges()",self.get)
        self.assertNotIn("data_buf->get_line_range(i)",self.get)
        self.assertNotIn("data_buf->get_line_count()",self.get)

    def test_existing_single_range_semantics_stay_unchanged(self):
        self.assertIn("_shape_lines()",self.single)
        self.assertIn("TS->shaped_text_get_range(lines_rid[p_line])",self.single)

    def test_method_is_declared_in_header(self):
        self.assertIn("Vector<Vector2i> get_line_ranges() const;",code("scene/resources/text_paragraph.h"))


if __name__=="__main__":
    unittest.main()
