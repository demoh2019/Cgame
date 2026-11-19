#!/usr/bin/env python3
"""Compile the actual String::repeat() implementation with an isolated C++ fixture.

The fixture replaces Godot's String storage, but not the production repeat()
algorithm. This catches syntax errors, bounds mistakes, and accidental changes
to emitted characters without needing the full engine build. Native doctests
remain the authoritative integration coverage.
"""
from __future__ import annotations

from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
SOURCE_PATH = ROOT / "core/string/ustring.cpp"

PREFIX = r"""
#include <algorithm>
#include <cassert>
#include <climits>
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>

constexpr int OK = 0;
#define MIN(a, b) std::min((a), (b))
#define ERR_FAIL_COND_V_MSG(condition, result, message) \
    do { if (condition) { return String(result); } } while (0)

class String {
    std::u32string chars;
public:
    static constexpr char32_t _null = 0;
    String() = default;
    String(const char *cstr) {
        if (cstr) {
            while (*cstr) chars.push_back(static_cast<unsigned char>(*cstr++));
            chars.push_back(U'\0');
        }
    }
    String(const char32_t *cstr) {
        if (cstr) {
            while (*cstr) chars.push_back(*cstr++);
            chars.push_back(U'\0');
        }
    }
    int length() const { return chars.empty() ? 0 : int(chars.size()) - 1; }
    bool is_empty() const { return length() == 0; }
    const char32_t *ptr() const { return chars.data(); }
    char32_t *ptrw() { return chars.data(); }
    int resize_uninitialized(int64_t size) {
        chars.resize(size_t(size));
        return OK;
    }
    char32_t at(int i) const { return chars.at(size_t(i)); }
    String repeat(int p_count) const;
};
"""

DRIVER = r"""
int main() {
    const String empty;
    assert(empty.repeat(99999).is_empty());
    const String abc("abc");
    assert(abc.repeat(0).is_empty());
    assert(abc.repeat(1).length() == 3);
    assert(abc.repeat(-1).is_empty());
    assert(abc.repeat(INT32_MAX).is_empty());
    for (int n = 1; n < 2500; ++n) {
        const String out = abc.repeat(n);
        assert(out.length() == 3 * n);
        assert(out.at(out.length()) == U'\0');
        for (int j = 0; j < out.length(); ++j) {
            assert(out.at(j) == U"abc"[j % 3]);
        }
    }

    const String unicode(U"αβ🚀");
    for (int n = 1; n < 1500; n += 17) {
        const String out = unicode.repeat(n);
        assert(out.length() == 3 * n);
        assert(out.at(out.length()) == 0);
        for (int j = 0; j < out.length(); ++j) {
            assert(out.at(j) == U"αβ🚀"[j % 3]);
        }
    }
    const String big = String("0123456789ABCDEF").repeat(100001);
    assert(big.length() == 1600016);
    assert(big.at(big.length()) == U'\0');
    for (int i = 0; i < big.length(); i += 127) {
        assert(big.at(i) == U"0123456789ABCDEF"[i % 16]);
    }
}
"""

def main() -> None:
    text = SOURCE_PATH.read_text(encoding="utf-8")
    begin = text.index("String String::repeat(int p_count) const {")
    end = text.index("\nString String::reverse() const {", begin)
    production_method = text[begin:end]

    compilers = [binary for binary in ("g++", "clang++") if shutil.which(binary)]
    if not compilers:
        raise RuntimeError("No supported C++ compiler found")

    with tempfile.TemporaryDirectory(prefix="cgame-repeat-") as temp:
        root = Path(temp)
        cpp = root / "test.cpp"
        cpp.write_text(PREFIX + "\n" + production_method + "\n" + DRIVER, encoding="utf-8")
        for compiler in compilers:
            executable = root / (compiler.replace("+", "p") + "-repeat")
            subprocess.run(
                [compiler, "-std=c++17", "-O2", "-Wall", "-Wextra", "-Werror",
                 "-o", str(executable), str(cpp)],
                check=True,
            )
            subprocess.run([str(executable)], check=True)
            print(f"{compiler}: production String::repeat passed 2,500 ASCII, "
                  "Unicode, 1.6M-character and invalid-size cases")

if __name__ == "__main__":
    main()
