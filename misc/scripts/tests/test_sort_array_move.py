"""Compile the real SortArray header with minimal engine stubs and exercise move semantics.

Unlike a source-shape assertion, this checks the edited production template with
both C++ compilers and both debug/release validation branches.
"""

from __future__ import annotations

import pathlib
import shutil
import subprocess
import tempfile
import textwrap
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[3]

TYPEDEFS = r"""
#pragma once
#include <algorithm>
#include <cstdint>
#include <utility>
template <typename T> struct Comparator {
    bool operator()(const T &a, const T &b) const { return a < b; }
};
#define SWAP(a, b) std::swap(a, b)
"""

ERROR_MACROS = r"""
#pragma once
#include <cstdlib>
#define unlikely(x) (x)
#define ERR_PRINT(x) do { (void)(x); std::abort(); } while (false)
"""

HARNESS = r"""
#include "core/templates/sort_array.h"
#include <algorithm>
#include <cassert>
#include <vector>
#include <cstdint>

struct Tracked {
    int key = 0;
    inline static int copies = 0;
    inline static int moves = 0;
    explicit Tracked(int k = 0) : key(k) {}
    Tracked(const Tracked &o) : key(o.key) { ++copies; }
    Tracked(Tracked &&o) noexcept : key(o.key) { ++moves; o.key = -999; }
    Tracked &operator=(const Tracked &o) {
        key = o.key; ++copies; return *this;
    }
    Tracked &operator=(Tracked &&o) noexcept {
        key = o.key; ++moves; o.key = -999; return *this;
    }
    bool operator<(const Tracked &o) const { return key < o.key; }
};

struct DecadeComparator {
    bool operator()(const Tracked &a, const Tracked &b) const {
        return a.key / 10 < b.key / 10;
    }
};

int main() {
    SortArray<Tracked> sorter;
    for (int n = 0; n <= 160; ++n) {
        std::vector<Tracked> data;
        std::vector<int> expected;
        data.reserve(n);
        for (int i = 0; i < n; ++i) {
            int v = ((i * 37 + n * 23) % 101) - 50;
            data.emplace_back(v);
            expected.push_back(v);
        }
        std::sort(expected.begin(), expected.end());
        Tracked::copies = 0;
        Tracked::moves = 0;
        sorter.sort(data.data(), n);
        for (int i = 0; i < n; ++i) assert(data[i].key == expected[i]);
        if (n >= 2 && n <= 16) assert(Tracked::copies == 0);
    }
    {
        Tracked data[16];
        for (int i = 0; i < 16; ++i) data[i].key = 15 - i;
        Tracked::copies = 0;
        Tracked::moves = 0;
        sorter.sort(data, 16);
        assert(Tracked::copies == 0);
        assert(Tracked::moves > 0);
        for (int i = 0; i < 16; ++i) assert(data[i].key == i);
    }
    // Already ordered small arrays must not move expensive values at all.
    // This checks the actual SortArray header in both debug and release.
    {
        Tracked ordered[16];
        for (int i = 0; i < 16; ++i) ordered[i].key = i;
        Tracked::copies = Tracked::moves = 0;
        sorter.sort(ordered, 16);
        assert(Tracked::copies == 0 && Tracked::moves == 0);
        for (int i = 0; i < 16; ++i) assert(ordered[i].key == i);
    }
    {
        Tracked repeated[16];
        for (int i = 0; i < 16; ++i) repeated[i].key = i / 4;
        Tracked::copies = Tracked::moves = 0;
        sorter.sort(repeated, 16);
        assert(Tracked::copies == 0 && Tracked::moves == 0);
    }
    {
        Tracked ordered[32];
        for (int i = 0; i < 32; ++i) ordered[i].key = i;
        Tracked::copies = Tracked::moves = 0;
        sorter.unguarded_linear_insert(31, ordered);
        assert(Tracked::copies == 0 && Tracked::moves == 0);
    }
    {
        Tracked nearly_ordered[16];
        for (int i = 0; i < 16; ++i) nearly_ordered[i].key = i;
        std::swap(nearly_ordered[13].key, nearly_ordered[14].key);
        Tracked::copies = Tracked::moves = 0;
        sorter.sort(nearly_ordered, 16);
        assert(Tracked::copies == 0 && Tracked::moves > 0);
        for (int i = 0; i < 16; ++i) assert(nearly_ordered[i].key == i);
    }
    {
        // All-equal large arrays are a common pathological introsort input:
        // avoid partition swaps and move-assignments completely.
        std::vector<Tracked> equal(512);
        for (Tracked &item : equal) item.key = 7;
        Tracked::copies = Tracked::moves = 0;
        sorter.sort(equal.data(), int64_t(equal.size()));
        assert(Tracked::copies == 0 && Tracked::moves == 0);
        for (const Tracked &item : equal) assert(item.key == 7);
    }
    {
        // The comparator, not the exact key, defines equivalence.
        std::vector<Tracked> equivalent(256);
        for (int i = 0; i < 256; ++i) equivalent[i].key = 100 + (i % 10);
        Tracked::copies = Tracked::moves = 0;
        SortArray<Tracked, DecadeComparator>().sort(equivalent.data(), int64_t(equivalent.size()));
        assert(Tracked::copies == 0 && Tracked::moves == 0);
        for (int i = 0; i < 256; ++i) assert(equivalent[i].key == 100 + (i % 10));
    }
    {
        // Matching endpoints and midpoint are not sufficient to skip sort.
        std::vector<Tracked> mixed(256);
        for (Tracked &item : mixed) item.key = 7;
        mixed[50].key = 3;
        mixed[180].key = 2;
        Tracked::copies = Tracked::moves = 0;
        sorter.sort(mixed.data(), int64_t(mixed.size()));
        assert(Tracked::copies == 0 && Tracked::moves > 0);
        for (int i = 1; i < 256; ++i) assert(mixed[i - 1].key <= mixed[i].key);
        assert(mixed.front().key == 2 && mixed.back().key == 7);
    }
    {
        // A middle subrange can skip without modifying its boundaries.
        std::vector<Tracked> range(130);
        for (Tracked &item : range) item.key = 7;
        range.front().key = 300;
        range.back().key = -200;
        Tracked::copies = Tracked::moves = 0;
        sorter.sort_range(1, 129, range.data());
        assert(Tracked::copies == 0 && Tracked::moves == 0);
        assert(range.front().key == 300 && range.back().key == -200);
    }
    for (int n = 1; n <= 64; ++n) {
        for (int k : {0, n / 2, n - 1}) {
            std::vector<Tracked> data;
            for (int i = 0; i < n; ++i) data.emplace_back((i * 17 + n * 3) % 23);
            sorter.nth_element(0, n, k, data.data());
            for (int i = 0; i < k; ++i) assert(data[i].key <= data[k].key);
            for (int i = k + 1; i < n; ++i) assert(data[i].key >= data[k].key);
        }
    }
    {
        Tracked data[12];
        for (int i = 0; i < 12; ++i) data[i].key = 11 - i;
        sorter.sort_range(2, 10, data);
        assert(data[0].key == 11 && data[1].key == 10);
        assert(data[10].key == 1 && data[11].key == 0);
        for (int i = 3; i < 10; ++i) assert(data[i - 1].key <= data[i].key);
    }
}
"""

class SortArrayMoveTests(unittest.TestCase):
    def verify(self, compiler: str, debug: bool) -> None:
        executable = shutil.which(compiler)
        if executable is None:
            self.skipTest(f"{compiler} is not available")
        with tempfile.TemporaryDirectory() as work:
            temp = pathlib.Path(work)
            (temp / "core" / "error").mkdir(parents=True)
            (temp / "core" / "typedefs.h").write_text(textwrap.dedent(TYPEDEFS))
            (temp / "core" / "error" / "error_macros.h").write_text(
                textwrap.dedent(ERROR_MACROS)
            )
            source = temp / "main.cpp"
            binary = temp / "test_sort_array"
            source.write_text(textwrap.dedent(HARNESS))
            command = [
                executable, "-std=c++17", "-O2", "-Wall", "-Wextra", "-Werror",
                "-I", str(temp), "-I", str(ROOT), str(source), "-o", str(binary),
            ]
            if debug:
                command.insert(1, "-DDEBUG_ENABLED")
            subprocess.run(command, check=True, capture_output=True, text=True, timeout=90)
            subprocess.run([str(binary)], check=True, capture_output=True, text=True, timeout=45)

    def test_gcc_release(self) -> None:
        self.verify("g++", False)

    def test_gcc_debug(self) -> None:
        self.verify("g++", True)

    def test_clang_release(self) -> None:
        self.verify("clang++", False)

    def test_clang_debug(self) -> None:
        self.verify("clang++", True)

if __name__ == "__main__":
    unittest.main()
