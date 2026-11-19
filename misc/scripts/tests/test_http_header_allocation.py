"""Regression contracts for low-allocation HTTP header value parsing."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
HTTP = (ROOT / "core/io/http_client_tcp.cpp").read_text(encoding="utf-8")
STR = (ROOT / "core/string/ustring.cpp").read_text(encoding="utf-8")
HDR = (ROOT / "core/string/ustring.h").read_text(encoding="utf-8")
NATIVE = (ROOT / "tests/core/string/test_string.cpp").read_text(encoding="utf-8")
BEGIN = HTTP.index("if (s.begins_with(\"content-length:\"))")
END = HTTP.index('} else if (s.begins_with("connection: close"))', BEGIN)
HEADER_BLOCK = HTTP[BEGIN:END]
STR_START = STR.index("Span<char32_t> String::strip_edges_span(")
STR_END = STR.index("String String::strip_escapes() const", STR_START)
TRIM_BLOCK = STR[STR_START:STR_END]

class HttpHeaderAllocationContracts(unittest.TestCase):
    def test_content_length_parsed_from_nonowning_view(self):
        self.assertIn("String::strip_edges_span(value, true, true)", HEADER_BLOCK)
        self.assertIn("String::to_int(value.ptr(), value.size())", HEADER_BLOCK)
        self.assertNotIn("s.substr(", HEADER_BLOCK)

    def test_transfer_encoding_uses_utf32_span_comparison(self):
        self.assertIn('Span<char32_t>(U"chunked")', HEADER_BLOCK)
        self.assertNotIn("header.substr(", HEADER_BLOCK)
        self.assertNotIn('String("chunked")', HEADER_BLOCK)

    def test_no_extra_terminator_appended_to_header(self):
        self.assertNotIn("response_str.push_back(0);", HTTP)

    def test_static_trim_helper_has_no_allocating_string(self):
        self.assertIn("static Span<char32_t> strip_edges_span(", HDR)
        self.assertNotIn("substr(", TRIM_BLOCK[:TRIM_BLOCK.index("String String::strip_edges(")])

    def test_trim_can_handle_empty_span(self):
        self.assertIn("if (p_span.is_empty())", TRIM_BLOCK)

    def test_right_trim_checks_the_first_character(self):
        self.assertIn("while (end > begin && p_span[end - 1] <= 32)", TRIM_BLOCK)
        self.assertNotIn("i > beg", TRIM_BLOCK)

    def test_existing_string_api_preserves_copy_on_no_trim(self):
        self.assertIn("return *this;", TRIM_BLOCK)

    def test_lifetime_of_nonowning_span_stays_with_live_header(self):
        self.assertIn("Span<char32_t> value(s.ptr() + prefix_length", HEADER_BLOCK)
        self.assertIn("String s = header.to_lower();", HTTP)

    def test_native_tests_cover_whitespace_and_utf32(self):
        self.assertIn("strip_edges_span matches String::strip_edges", NATIVE)
        self.assertIn("strip_edges_span trims a single trailing whitespace character", NATIVE)
        self.assertIn("Привет 🌎", NATIVE)

if __name__ == "__main__":
    unittest.main()
