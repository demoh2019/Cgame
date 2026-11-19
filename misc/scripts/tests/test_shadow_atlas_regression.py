#!/usr/bin/env python3
"""Fast isolated checks for the two shadow-atlas fallbacks from upstream #125577."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
SOURCES = (
    "drivers/gles3/storage/light_storage.cpp",
    "servers/rendering/renderer_rd/storage_rd/light_storage.cpp",
)

def extract_failed_reallocation_branch(source):
    marker = "// No better slot was found, so the light keeps its slot;"
    start = source.find(marker)
    if start == -1:
        raise ValueError("Missing failed-reallocation fix")
    opening = source.rfind("if (old_quadrant != SHADOW_INVALID) {", 0, start)
    if opening == -1:
        raise ValueError("Fallback lacks a validity check")
    closing = source.find("\n\t}", start)
    if closing == -1:
        raise ValueError("Fallback block is incomplete")
    body = source[opening : closing + 3]
    if "shadows.write[old_shadow].version = p_light_version;" not in body:
        raise ValueError("Fallback does not update the retained shadow's version")
    after = source[closing + 3 : closing + 120].strip()
    if not after.startswith("return should_redraw;"):
        raise ValueError("Fallback does not run before the return")
    return body

def make_cpp_test(branch):
    return r"""
#include <cassert>
#include <cstdint>
constexpr uint32_t SHADOW_INVALID = UINT32_MAX;
struct Shadow { uint64_t version = 0; };
struct ShadowArray { Shadow write[3]; };
struct Quadrant { ShadowArray shadows; };
struct Atlas { Quadrant quadrants[2]; };
bool update(Atlas &atlas, uint32_t old_quadrant, uint32_t old_shadow, uint64_t p_light_version) {
    Atlas *shadow_atlas = &atlas;
    const bool should_redraw = old_quadrant != SHADOW_INVALID &&
        shadow_atlas->quadrants[old_quadrant].shadows.write[old_shadow].version != p_light_version;
""" + branch + r"""
    return should_redraw;
}
int main() {
    Atlas a;
    a.quadrants[0].shadows.write[0].version = 4;
    a.quadrants[0].shadows.write[1].version = 123;
    a.quadrants[1].shadows.write[0].version = 456;
    assert(update(a, 0, 0, 5));  // First changed version draws once.
    assert(a.quadrants[0].shadows.write[0].version == 5);
    assert(!update(a, 0, 0, 5)); // Unchanged version avoids perpetual redraw.
    assert(update(a, 0, 0, 6));  // A later change triggers exactly one new redraw.
    assert(!update(a, 0, 0, 6));
    assert(a.quadrants[0].shadows.write[1].version == 123);
    assert(a.quadrants[1].shadows.write[0].version == 456);
    assert(!update(a, SHADOW_INVALID, 0, 9)); // No old slot must never be indexed.
    return 0;
}
"""

class ShadowAtlasRegression(unittest.TestCase):
    def test_both_backends_use_identical_fallback(self):
        bodies=[extract_failed_reallocation_branch((ROOT / p).read_text()) for p in SOURCES]
        self.assertEqual(bodies[0], bodies[1])

    def test_each_backend_updates_retained_slot_once_per_version(self):
        compiler = shutil.which(os.environ.get("CXX", "c++"))
        if compiler is None:
            self.skipTest("C++ compiler unavailable")
        for path in SOURCES:
            with self.subTest(path=path), tempfile.TemporaryDirectory() as temp_dir:
                branch=extract_failed_reallocation_branch((ROOT / path).read_text())
                code=make_cpp_test(branch)
                executable=Path(temp_dir) / "atlas_test"
                result=subprocess.run(
                    [compiler, "-std=c++17", "-Wall", "-Wextra", "-Werror", "-x", "c++", "-", "-o", str(executable)],
                    input=code, capture_output=True, text=True, timeout=30,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                result=subprocess.run([str(executable)], capture_output=True, text=True, timeout=15)
                self.assertEqual(result.returncode, 0, result.stderr)

if __name__ == "__main__":
    unittest.main()