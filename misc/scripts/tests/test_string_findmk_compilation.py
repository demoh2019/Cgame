#!/usr/bin/env python3
"""Compile and execute the actual String::findmk() overload with minimal String stubs.

This exercises production search control flow, including Unicode, duplicates,
empty needles and search-offset bounds. Native Godot doctests are still required.
"""
from __future__ import annotations

from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "core/string/ustring.cpp"

PREFIX = r"""
#include <cassert>
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>

class String {
    std::u32string storage;
public:
    String() = default;
    String(const std::u32string &value) : storage(value) {}
    String(const char32_t *value) : storage(value ? value : U"") {}
    String(const char *value) {
        while (value && *value) storage.push_back(static_cast<unsigned char>(*value++));
    }
    int length() const { return int(storage.size()); }
    const char32_t *get_data() const { return storage.c_str(); }
    const std::u32string &value() const { return storage; }
};
template <typename T> class Vector {
    std::vector<T> storage;
public:
    bool is_empty() const { return storage.empty(); }
    int size() const { return int(storage.size()); }
    const T *ptr() const { return storage.data(); }
    void push_back(const T &value) { storage.push_back(value); }
    const T &operator[](int index) const { return storage[size_t(index)]; }
};
static bool are_spans_equal(const char32_t *a, const char32_t *b, size_t len) {
    return len == 0 || std::memcmp(a, b, len * sizeof(char32_t)) == 0;
}
int String_findmk_reference(const String &haystack, const Vector<String> &needles, int from, int *key) {
    if (from < 0 || haystack.length() == 0 || needles.is_empty()) return -1;
    for (int i = from; i < haystack.length(); ++i) {
        for (int j = 0; j < needles.size(); ++j) {
            const int size = needles[j].length();
            if (size <= haystack.length() - i &&
                (size == 0 || haystack.value().compare(size_t(i), size_t(size),
                                                      needles[j].value()) == 0)) {
                if (key) *key = j;
                return i;
            }
        }
    }
    return -1;
}
"""

DRIVER = r"""
int main() {
    uint32_t rng = 0x9e3779b9;
    const auto next = [&rng]() -> uint32_t {
        rng ^= rng << 13; rng ^= rng >> 17; rng ^= rng << 5; return rng;
    };
    for (int trial = 0; trial < 4000; ++trial) {
        std::u32string text;
        const int length = int(next() % 150);
        for (int i = 0; i < length; ++i) {
            const char32_t letters[] = { U'a', U'β', U'🚀', U'x', U'9' };
            text.push_back(letters[next() % 5]);
        }
        const String haystack(text);
        Vector<String> keys;
        const int key_count = int(next() % 22);
        for (int k = 0; k < key_count; ++k) {
            std::u32string needle;
            const int n = int(next() % 9);
            for (int j = 0; j < n; ++j) {
                const char32_t letters[] = { U'a', U'β', U'🚀', U'x', U'9' };
                needle.push_back(letters[next() % 5]);
            }
            keys.push_back(String(needle));
        }
        for (int from : {-3, 0, 1, 10, length - 1, length, length + 1}) {
            int actual_key = -123;
            int expected_key = -123;
            const int actual = haystack.findmk(keys, from, &actual_key);
            const int expected = String_findmk_reference(haystack, keys, from, &expected_key);
            assert(actual == expected);
            assert(actual_key == expected_key);
            assert(haystack.findmk(keys, from, nullptr) == expected);
        }
    }
}
"""

def main() -> None:
    text = SOURCE.read_text(encoding="utf-8")
    begin = text.index("int String::findmk(const Vector<String> &p_keys, int p_from, int *r_key) const {")
    end = text.index("\nint String::findn(", begin)
    method = text[begin:end]
    # A tiny free-function wrapper is needed because the Cgame method is not in
    # our minimal substitute's declaration until we add its real signature.
    prefix = PREFIX.replace(
        "    const std::u32string &value() const { return storage; }",
        "    const std::u32string &value() const { return storage; }\n"
        "    int findmk(const Vector<String> &keys, int from, int *key) const;",
    )
    # Vector must be forward-declared before the String declaration.
    prefix = prefix.replace("class String {", "template <typename T> class Vector;\nclass String {")
    with tempfile.TemporaryDirectory(prefix="cgame-findmk-") as temp:
        root = Path(temp)
        source = root / "test.cpp"
        source.write_text(prefix + "\n" + method + "\n" + DRIVER, encoding="utf-8")
        compilers = [name for name in ("g++", "clang++") if shutil.which(name)]
        if not compilers:
            raise RuntimeError("No C++ compiler found")
        for compiler in compilers:
            target = root / (compiler.replace("+", "p") + "-test")
            subprocess.run([compiler, "-std=c++17", "-O2", "-Wall",
                            "-Wextra", "-Werror", str(source), "-o", str(target)],
                           check=True)
            subprocess.run([str(target)], check=True)
            print(f"{compiler}: 4,000 randomized Unicode/multi-key search cases passed")

if __name__ == "__main__":
    main()
