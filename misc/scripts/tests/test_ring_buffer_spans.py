#!/usr/bin/env python3
"""Compile and exercise the actual production RingBuffer header with minimal Godot stubs.

This fast test is not a substitute for the native Godot doctest suite; it makes the
template implementation executable on both GCC and Clang without building the engine.
"""
from __future__ import annotations

import pathlib
import shutil
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[3]

SHIM = r"""
#pragma once
#include <algorithm>
#include <cstdint>
#include <vector>
#define _WARN_UNUSED_
#define _FORCE_INLINE_ inline
#define MIN(a, b) std::min((a), (b))
#define ERR_FAIL_COND_V(condition, retval) do { if (condition) return (retval); } while (false)
enum Error { OK, FAILED };
template <typename T> class LocalVector {
    std::vector<T> storage;
public:
    void resize(int64_t amount) { storage.resize(size_t(amount)); }
    int size() const { return int(storage.size()); }
    T *ptr() { return storage.data(); }
    const T *ptr() const { return storage.data(); }
    T &operator[](int index) { return storage[index]; }
    const T &operator[](int index) const { return storage[index]; }
};
"""

DRIVER = r"""
#include "ring_buffer.h"
#include <cassert>
#include <climits>
#include <cstdint>
#include <deque>
#include <string>

int main() {
    RingBuffer<uint8_t> ring(7);
    std::deque<uint8_t> expected;
    uint32_t seed = 0x1234abcd;
    for (int step = 0; step < 4000; ++step) {
        seed = seed * 1664525u + 1013904223u;
        const int count = int((seed >> 8) & 63u);
        if ((seed & 1u) != 0u) {
            uint8_t source[64];
            for (int i = 0; i < count; ++i) {
                source[i] = uint8_t((seed >> 16) + uint32_t(i * 17));
            }
            const int writable = std::min(count, 127 - int(expected.size()));
            assert(ring.write(source, count) == writable);
            for (int i = 0; i < writable; ++i) expected.push_back(source[i]);
        } else {
            uint8_t output[64] = {};
            const int readable = std::min(count, int(expected.size()));
            assert(ring.read(output, count) == readable);
            for (int i = 0; i < readable; ++i) {
                assert(output[i] == expected.front());
                expected.pop_front();
            }
        }
        assert(ring.data_left() == int(expected.size()));
        uint8_t peek[128] = {};
        assert(ring.copy(peek, 0, int(expected.size())) == int(expected.size()));
        for (int i = 0; i < int(expected.size()); ++i) assert(peek[i] == expected[i]);

        const int offset = expected.empty() ? 0 : int((seed >> 20) % expected.size());
        const int limit = int((seed >> 12) & 127u);
        const uint8_t needle = uint8_t(seed >> 24);
        int match = -1;
        for (int i = offset; i < int(expected.size()) && i - offset < limit; ++i) {
            if (expected[i] == needle) { match = i - offset; break; }
        }
        assert(ring.find(needle, offset, limit) == match);
    }

    RingBuffer<uint8_t> wrap(6);
    uint8_t first[45] = {};
    for (auto &item : first) item = 0x11;
    assert(wrap.write(first, 45) == 45);
    assert(wrap.advance_read(40) == 40);
    uint8_t next[40] = {};
    for (auto &item : next) item = 0x22;
    next[32] = 0xef;
    next[39] = 0xf0;
    assert(wrap.write(next, 40) == 40);
    assert(wrap.find(uint8_t(0xef), 0, INT_MAX) == 37);
    assert(wrap.find(uint8_t(0xf0), 0, INT_MAX) == 44);
    assert(wrap.find(uint8_t(0xef), 10, 35) == 27);
    assert(wrap.find(uint8_t(0xef), 38, 7) == -1);
    assert(wrap.find(uint8_t(0xef), -1, 45) == -1);
    assert(wrap.find(uint8_t(0xef), INT_MAX, INT_MAX) == -1);
    uint8_t output[] = { 99, 99 };
    assert(wrap.copy(output, -1, 2) == 0);
    assert(wrap.copy(output, INT_MAX, INT_MAX) == 0);
    assert(output[0] == 99);

    RingBuffer<int8_t> signed_ring(6);
    int8_t signed_values[40] = {};
    for (auto &item : signed_values) item = -2;
    signed_values[31] = -1;
    assert(signed_ring.write(signed_values, 40) == 40);
    assert(signed_ring.find(int8_t(-1), 0, INT_MAX) == 31);

    RingBuffer<std::string> nontrivial(3);
    const std::string words[] = { "a", "b", "c", "d", "e", "f" };
    assert(nontrivial.write(words, 6) == 6);
    assert(nontrivial.advance_read(5) == 5);
    const std::string next_words[] = { "g", "h", "i", "j", "k" };
    assert(nontrivial.write(next_words, 5) == 5);
    assert(nontrivial.find(std::string("k"), 0, 6) == 5);
    std::string strings[6];
    assert(nontrivial.read(strings, 6) == 6);
    assert(strings[0] == "f" && strings[5] == "k");
}
"""

def main() -> None:
    original = (ROOT / "core/templates/ring_buffer.h").read_text()
    include = '#include "core/templates/local_vector.h"'
    if original.count(include) != 1:
        raise AssertionError("Expected exactly one LocalVector include in production header")
    # Keep all production code and replace only its unrelated engine dependency.
    standalone = original.replace(include, '#include "ring_buffer_test_shim.h"')
    compilers = [c for c in ("g++", "clang++") if shutil.which(c)]
    if not compilers:
        raise RuntimeError("C++ compiler missing")
    with tempfile.TemporaryDirectory(prefix="cgame-ring-buffer-") as folder:
        root = pathlib.Path(folder)
        (root / "ring_buffer.h").write_text(standalone)
        (root / "ring_buffer_test_shim.h").write_text(SHIM)
        (root / "main.cpp").write_text(DRIVER)
        for compiler in compilers:
            binary = root / (compiler.replace("+", "p") + "-test")
            subprocess.run(
                [compiler, "-std=c++17", "-O2", "-Wall", "-Wextra",
                 "-Werror", "-o", str(binary), str(root / "main.cpp")],
                check=True,
            )
            subprocess.run([str(binary)], check=True)
            print(f"{compiler}: 4000 differential operations and wrap/bounds tests passed")

if __name__ == "__main__":
    main()
