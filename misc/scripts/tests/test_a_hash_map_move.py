"""Compile the real upstream-derived AHashMap move-assignment body with ownership checks.

The harness extracts the function verbatim from the production header. It tests
storage transfer, self-move, repeated moves and destruction with two compilers.
"""

from __future__ import annotations

import pathlib
import shutil
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[3]
SOURCE = ROOT / "core/templates/a_hash_map.h"

def extract_move_assignment() -> str:
    contents = SOURCE.read_text(encoding="utf-8")
    start = contents.find("void operator=(AHashMap &&p_other)")
    if start < 0:
        raise AssertionError("AHashMap must expose a move-assignment overload")
    brace = contents.index("{", start)
    depth = 0
    for index in range(brace, len(contents)):
        char = contents[index]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return contents[start : index + 1]
    raise AssertionError("Unterminated move-assignment body")

BEFORE = r"""
#include <algorithm>
#include <cassert>
#include <cstdint>
#include <utility>
#define SWAP(a,b) std::swap(a,b)
struct AHashMap {
    int *_elements = nullptr;
    uint32_t *_metadata = nullptr;
    uint32_t _capacity_mask = 0;
    uint32_t _size = 0;
    inline static int allocations = 0;
    explicit AHashMap(int seed = 0) {
        if (seed != 0) {
            _elements = new int[1]{seed};
            _metadata = new uint32_t[1]{static_cast<uint32_t>(seed)};
            _capacity_mask = 7;
            _size = 1;
            allocations += 2;
        }
    }
    AHashMap(const AHashMap &) = delete;
    AHashMap &operator=(const AHashMap &) = delete;
    ~AHashMap() {
        delete[] _elements;
        delete[] _metadata;
    }
"""

AFTER = r"""
};
int main() {
    for (int i = 1; i < 1000; ++i) {
        AHashMap a(i), b(i + 1000);
        int *a_storage = a._elements;
        int *b_storage = b._elements;
        uint32_t *a_metadata = a._metadata;
        uint32_t *b_metadata = b._metadata;
        int allocation_count = AHashMap::allocations;

        a = std::move(b);
        assert(a._elements == b_storage && b._elements == a_storage);
        assert(a._metadata == b_metadata && b._metadata == a_metadata);
        assert(a._size == 1 && b._size == 1);
        assert(*a._elements == i + 1000 && *b._elements == i);
        assert(AHashMap::allocations == allocation_count);

        AHashMap &self_alias = a;
        a = std::move(self_alias);
        assert(a._elements == b_storage && *a._elements == i + 1000);
        assert(AHashMap::allocations == allocation_count);

        b = std::move(a);
        assert(b._elements == b_storage && a._elements == a_storage);
        assert(*b._elements == i + 1000 && *a._elements == i);
    }
    {
        AHashMap empty;
        AHashMap full(42);
        int *storage = full._elements;
        full = std::move(empty);
        assert(full._elements == nullptr && full._size == 0);
        assert(empty._elements == storage && *empty._elements == 42);
        empty = std::move(full);
        assert(full._elements == storage && *full._elements == 42);
    }
}
"""

class AHashMapMoveAssignmentTests(unittest.TestCase):
    def verify_compiler(self, compiler: str, optimize: bool) -> None:
        executable = shutil.which(compiler)
        if not executable:
            self.skipTest(f"{compiler} not installed")
        with tempfile.TemporaryDirectory() as path:
            source = pathlib.Path(path) / "move_assignment.cpp"
            binary = pathlib.Path(path) / "move_assignment"
            source.write_text(BEFORE + extract_move_assignment() + AFTER)
            cmd = [
                executable, "-std=c++17", "-Wall", "-Wextra", "-Werror",
                "-O2" if optimize else "-O0", str(source), "-o", str(binary),
            ]
            subprocess.run(cmd, check=True, capture_output=True, text=True, timeout=60)
            subprocess.run([str(binary)], check=True, capture_output=True, text=True, timeout=45)

    def test_gcc_debug(self) -> None:
        self.verify_compiler("g++", False)

    def test_gcc_optimized(self) -> None:
        self.verify_compiler("g++", True)

    def test_clang_debug(self) -> None:
        self.verify_compiler("clang++", False)

    def test_clang_optimized(self) -> None:
        self.verify_compiler("clang++", True)

if __name__ == "__main__":
    unittest.main()
