#!/usr/bin/env python3
"""Compile the production ASCII-header matcher independently of Godot builds.

This checks the actual production header with a minimal Span stub, and guards
HTTPClientTCP's call sites. Native C++ tests exercise Godot's real String/Span.
"""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "core/io/http_client_tcp.cpp"
HEADER = ROOT / "core/io/http_header_utils.h"
NATIVE = ROOT / "tests/core/io/test_http_header_utils.cpp"

class TestHTTPHeaderNoLowercase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source = SOURCE.read_text(encoding="utf-8")
        begin = source.index("for (int i = 0; i < responses.size(); i++)")
        end = source.index('if (i == 0 && responses[i].begins_with("HTTP"))', begin)
        cls.parser = source[begin:end]
        cls.header = HEADER.read_text(encoding="utf-8")

    def test_no_per_header_lowercase_allocation(self):
        self.assertNotIn(".to_lower()", self.parser)
        self.assertNotIn("String s = ", self.parser)
        self.assertIn("String header = responses[i].strip_edges();", self.parser)
        self.assertEqual(self.parser.count("HTTPHeaderUtils::matches_ascii_case_insensitive("), 4)

    def test_original_token_semantics_preserved(self):
        for value in ('"content-length:"', '"transfer-encoding:"', '"chunked", true', '"connection: close"'):
            self.assertIn(value, self.parser)
        self.assertIn("String::to_int(value.ptr(), value.size())", self.parser)
        self.assertIn("String::strip_edges_span(value, true, true)", self.parser)

    def test_production_matcher_has_no_string_allocations(self):
        self.assertIn("inline bool matches_ascii_case_insensitive(", self.header)
        self.assertIn("character >= U'A' && character <= U'Z'", self.header)
        self.assertIn("return !p_exact || i == p_text.size();", self.header)
        self.assertNotIn("String", self.header)

    def test_native_coverage(self):
        code = NATIVE.read_text(encoding="utf-8")
        self.assertEqual(code.count('TEST_CASE("[HTTPHeaderFast]'), 8)
        self.assertIn("TEST_FORCE_LINK(test_http_header_utils)", code)

    def test_production_header_compiles_and_matches_ascii_reference(self):
        span = """#pragma once
#include <cstdint>
template <class T> class Span {
    T *data_;
    std::uint64_t size_;
public:
    Span(T *p, std::uint64_t n) : data_(p), size_(n) {}
    std::uint64_t size() const { return size_; }
    T &operator[](std::uint64_t i) const { return data_[i]; }
};
"""
        harness = r"""
#include "core/io/http_header_utils.h"
#include <cassert>
#include <iostream>
#include <string>
#include <string_view>

static bool matches(std::u32string &s, const char *p, bool exact = false) {
    return HTTPHeaderUtils::matches_ascii_case_insensitive(
        Span<char32_t>(s.data(), s.size()), p, exact);
}
int main() {
    std::u32string s = U"CONTENT-LENGTH: 123";
    assert(matches(s, "content-length:"));
    assert(!matches(s, "transfer-encoding:"));
    assert(!matches(s, "content-length:", true));
    s = U"cOnTeNt-LeNgTh:";
    assert(matches(s, "content-length:", true));
    s = U"CHUNKED";
    assert(matches(s, "chunked", true));
    s = U"CHUNKED, gzip";
    assert(!matches(s, "chunked", true));
    s = U"Connection: Closed";
    assert(matches(s, "connection: close"));
    s = U"connection: open";
    assert(!matches(s, "connection: close"));
    s = U"";
    assert(matches(s, "", true));
    assert(!matches(s, "content-length:", false));
    s = U"content-lengt";
    assert(!matches(s, "content-length:", false));
    s = U"c\u00f3ntent-length: 10";
    assert(!matches(s, "content-length:", false));

    // Exhaustive ASCII case combinations for 13 characters of the header.
    for (unsigned bits = 0; bits < 8192; ++bits) {
        s = U"content-length: 123";
        for (unsigned i = 0; i < 13; ++i) {
            if (bits & (1u << i)) {
                if (s[i] >= U'a' && s[i] <= U'z') s[i] -= U'a' - U'A';
            }
        }
        assert(matches(s, "content-length:"));
    }
    std::cout << "PASS: 8192 case combinations and prefix/token boundaries\n";
}
"""
        with tempfile.TemporaryDirectory(prefix="cgame_http_ascii_") as td:
            work = Path(td)
            (work / "core/templates").mkdir(parents=True)
            (work / "core/io").mkdir(parents=True)
            (work / "core/templates/span.h").write_text(span, encoding="utf-8")
            (work / "core/io/http_header_utils.h").write_text(self.header, encoding="utf-8")
            src = work / "main.cpp"
            binary = work / "match"
            src.write_text(harness, encoding="utf-8")
            subprocess.run(
                [os.environ.get("CXX", "c++"), "-std=c++17", "-O2", "-Wall",
                 "-Wextra", "-Werror", "-I", str(work), str(src), "-o", str(binary)],
                check=True, timeout=60,
            )
            subprocess.run([str(binary)], check=True, timeout=30)


if __name__ == "__main__":
    unittest.main()
