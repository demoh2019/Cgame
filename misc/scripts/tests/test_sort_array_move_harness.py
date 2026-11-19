#!/usr/bin/env python3
"""Compile and exercise the production SortArray header with GCC or Clang.

Use isolated substitutes for Godot's error/log and comparator macros; do not
replace the SortArray implementation. Native doctests run in engine CI too.
"""
from pathlib import Path
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
HEADER = ROOT / "core/templates/sort_array.h"
header = HEADER.read_text(encoding="utf-8").replace("#pragma once", "")
for include in ('#include "core/error/error_macros.h"', '#include "core/typedefs.h"'):
    if header.count(include) != 1:
        raise RuntimeError("Unexpected SortArray include: " + include)
    header = header.replace(include, "")
if '#include "' in header:
    raise RuntimeError("SortArray gained another Godot dependency; update harness")

PROLOGUE = r"""
#include <algorithm>
#include <cassert>
#include <cstdint>
#include <iostream>
#include <random>
#include <string>
#include <utility>
#include <vector>
#define unlikely(x) (x)
#define ERR_PRINT(...) ((void)0)
#define SWAP(a, b) std::swap(a, b)
template <typename T> struct Comparator {
    bool operator()(const T &a, const T &b) const { return a < b; }
};
"""

TEST = r"""
struct Item {
    std::string payload;
    int key = 0;
    static inline int copies = 0;
    static inline int moves = 0;
    Item() = default;
    Item(int value) : payload(128, char('a' + value % 26)), key(value) {}
    Item(const Item &v) : payload(v.payload), key(v.key) { ++copies; }
    Item(Item &&v) noexcept : payload(std::move(v.payload)), key(v.key) { ++moves; }
    Item &operator=(const Item &v) {
        payload = v.payload; key = v.key; ++copies; return *this;
    }
    Item &operator=(Item &&v) noexcept {
        payload = std::move(v.payload); key = v.key; ++moves; return *this;
    }
    bool operator<(const Item &v) const { return key < v.key; }
};
struct Descending {
    bool operator()(const Item &a, const Item &b) const { return a.key > b.key; }
};
void verify(const std::vector<int> &input) {
    std::vector<Item> elements;
    for (int key : input) elements.emplace_back(key);
    std::vector<int> expected = input;
    std::sort(expected.begin(), expected.end());
    Item::copies = Item::moves = 0;
    SortArray<Item>().sort(elements.data(), elements.size());
    if (input.size() <= 16) assert(Item::copies == 0);
    assert(elements.size() == expected.size());
    for (size_t i = 0; i < elements.size(); ++i) {
        assert(elements[i].key == expected[i]);
        assert(elements[i].payload == std::string(128, char('a' + expected[i] % 26)));
    }
}
int main() {
    SortArray<int>().sort(nullptr, 0);
    int count = 0;
    for (int length = 0; length <= 9; ++length) {
        int possibilities = 1;
        for (int i = 0; i < length; ++i) possibilities *= 3;
        for (int mask = 0; mask < possibilities; ++mask) {
            std::vector<int> data(length);
            int encoded = mask;
            for (int &key : data) { key = encoded % 3; encoded /= 3; }
            verify(data);
            ++count;
        }
    }
    std::mt19937 rng(123456);
    for (int length : {10, 15, 16, 17, 32, 64, 127}) {
        for (int run = 0; run < 1000; ++run) {
            std::vector<int> data(length);
            for (int &key : data) key = int(rng() % 10);
            verify(data);
            ++count;
        }
    }
    Item reversed[] = {Item(1), Item(3), Item(2), Item(0)};
    Item::copies = 0;
    SortArray<Item, Descending>().sort(reversed, 4);
    assert(Item::copies == 0);
    for (int i = 0; i < 4; ++i) assert(reversed[i].key == 3 - i);
    Item bounded[] = {Item(9), Item(3), Item(2), Item(1), Item(8)};
    Item::copies = 0;
    SortArray<Item>().sort_range(1, 4, bounded);
    assert(Item::copies == 0);
    for (int i = 0; i < 5; ++i) {
        assert(bounded[i].key == (i == 0 ? 9 : (i == 4 ? 8 : i)));
    }

    // Exercise unbalanced partitions, repeated keys and large arrays against
    // std::sort with the *actual* SortArray header on both compilers.
    assert(SortArray<int>().bitlog(0) == 0);
    assert(SortArray<int>().bitlog(1) == 0);
    assert(SortArray<int>().bitlog(2) == 1);
    assert(SortArray<int>().bitlog((int64_t(1) << 40)) == 40);
    for (int length : {17, 18, 31, 32, 33, 256, 1023, 65536}) {
        for (int pattern = 0; pattern < 7; ++pattern) {
            std::vector<int> data(length);
            for (int i = 0; i < length; ++i) {
                switch (pattern) {
                    case 0: data[i] = i; break;
                    case 1: data[i] = length - i; break;
                    case 2: data[i] = i & 3; break;
                    case 3: data[i] = std::min(i, length - 1 - i); break;
                    case 4: data[i] = i % 257; break;
                    case 5: data[i] = (i & 1) ? -1000 : 1000; break;
                    default: data[i] = (i * 7793) % 65521; break;
                }
            }
            const auto expected = [&]() {
                auto result = data;
                std::sort(result.begin(), result.end());
                return result;
            }();
            SortArray<int>().sort(data.data(), data.size());
            assert(data == expected);
            ++count;
        }
    }
    std::cout << count << " production-header cases passed\\n";
}
"""

with tempfile.TemporaryDirectory(prefix="cgame_sort_moves_") as directory:
    source = Path(directory) / "test.cpp"
    executable = Path(directory) / "test"
    source.write_text(PROLOGUE + header + TEST, encoding="utf-8")
    compiler = os.environ.get("CXX", "c++")
    subprocess.run(
        [compiler, "-std=c++17", "-O2", "-Wall", "-Wextra", "-Werror", str(source), "-o", str(executable)],
        check=True,
    )
    subprocess.run([str(executable)], check=True)
