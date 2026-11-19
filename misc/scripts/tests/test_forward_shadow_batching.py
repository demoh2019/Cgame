#!/usr/bin/env python3
"""Regression contracts and compiled model of Forward+ shadow batch keys.

This compiles the exact depth-layer selection and can_repeat_with expression
extracted from Cgame's C++ sources. It is NOT a GPU benchmark. Real draw-call
counts and image equivalence must be measured on Vulkan/D3D12 hardware.
"""
from pathlib import Path
import os
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
CPP = ROOT / "servers/rendering/renderer_rd/forward_clustered/render_forward_clustered.cpp"
HEADER = ROOT / "servers/rendering/renderer_rd/forward_clustered/render_forward_clustered.h"


class TestShadowBatching(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = CPP.read_text(encoding="utf-8")
        cls.header = HEADER.read_text(encoding="utf-8")

    def test_shadow_depth_layer_zero_only_for_shadow_passes(self):
        expected = (
            "surf->sort.depth_layer = "
            "(p_pass_mode == PASS_MODE_SHADOW || p_pass_mode == PASS_MODE_SHADOW_DP) ? 0 : depth_layer;"
        )
        self.assertEqual(self.source.count(expected), 1)

    def test_shadow_passes_still_select_shadow_surfaces(self):
        self.assertIn(
            "p_pass_mode == PASS_MODE_SHADOW || p_pass_mode == PASS_MODE_SHADOW_DP",
            self.source
        )
        self.assertIn("GeometryInstanceSurfaceDataCache::FLAG_PASS_SHADOW", self.source)

    def test_batch_compatibility_checks_preserved(self):
        section = self.source[
            self.source.index("const bool cant_repeat =") :
            self.source.index("repeats++;", self.source.index("const bool cant_repeat ="))
        ]
        self.assertIn("prev_surface->can_repeat_with(*surface)", section)
        self.assertIn("inst->mirror == prev_surface->owner->mirror", section)
        self.assertIn("repeats < RenderElementInfo::MAX_REPEATS", section)
        self.assertIn("!cant_repeat", section)

    def test_sort_keys_and_lightmap_checks_are_unchanged(self):
        signature = "bool can_repeat_with(const GeometryInstanceSurfaceDataCache &p_other) const"
        self.assertIn(signature, self.header)
        body = self.header.split(signature, 1)[1].split("}", 1)[0]
        for key in (
            "sort.sort_key1 == p_other.sort.sort_key1",
            "sort.sort_key2 == p_other.sort.sort_key2",
            "uses_lightmap_specular == p_other.uses_lightmap_specular",
        ):
            self.assertIn(key, body)

    def test_compiled_production_expressions_with_gcc_or_clang(self):
        layer = re.search(
            r"surf->sort\.depth_layer\s*=\s*([^;]+);", self.source
        )
        compatibility = re.search(
            r"bool can_repeat_with\(const GeometryInstanceSurfaceDataCache &p_other\) const\s*\{\s*return\s+([^;]+);",
            self.header
        )
        self.assertIsNotNone(layer)
        self.assertIsNotNone(compatibility)
        layer_expr = layer.group(1)
        repeat_expr = compatibility.group(1)
        cpp = r"""
#include <algorithm>
#include <cassert>
#include <cstdint>
#include <iostream>
#include <vector>

enum PassMode { PASS_MODE_COLOR, PASS_MODE_SHADOW, PASS_MODE_SHADOW_DP, PASS_MODE_DEPTH, PASS_MODE_DEPTH_MATERIAL };
struct GeometryInstanceSurfaceDataCache {
    struct Sort { uint64_t sort_key1 = 0, sort_key2 = 0; } sort;
    bool uses_lightmap_specular = false;
    bool can_repeat_with(const GeometryInstanceSurfaceDataCache &p_other) const {
        return REPEAT_EXPRESSION;
    }
};
uint64_t make_key(int lod, int depth) {
    return (uint64_t(lod) << 16) | (uint64_t(depth) << 12) | 3u;
}
int batches(std::vector<GeometryInstanceSurfaceDataCache> &surfaces) {
    std::sort(surfaces.begin(), surfaces.end(), [](const auto &a, const auto &b) {
        if (a.sort.sort_key1 != b.sort.sort_key1) return a.sort.sort_key1 < b.sort.sort_key1;
        return a.sort.sort_key2 < b.sort.sort_key2;
    });
    int calls = 0;
    for (size_t i = 0; i < surfaces.size(); ++i) {
        if (!i || !surfaces[i - 1].can_repeat_with(surfaces[i])) ++calls;
    }
    return calls;
}
int main() {
    for (int mode = PASS_MODE_COLOR; mode <= PASS_MODE_DEPTH_MATERIAL; ++mode) {
        for (int depth_layer = 0; depth_layer < 16; ++depth_layer) {
            const PassMode p_pass_mode = PassMode(mode);
            const int selected = DEPTH_EXPRESSION;
            const int expected = (mode == PASS_MODE_SHADOW || mode == PASS_MODE_SHADOW_DP) ? 0 : depth_layer;
            assert(selected == expected);
        }
    }
    for (int mode : { PASS_MODE_SHADOW, PASS_MODE_SHADOW_DP, PASS_MODE_COLOR }) {
        std::vector<GeometryInstanceSurfaceDataCache> surfaces;
        for (int lod = 1; lod <= 2; ++lod) {
            for (int depth_layer = 0; depth_layer < 16; ++depth_layer) {
                for (int n = 0; n < 64; ++n) {
                    const PassMode p_pass_mode = PassMode(mode);
                    const int selected = DEPTH_EXPRESSION;
                    GeometryInstanceSurfaceDataCache surface;
                    surface.sort.sort_key1 = make_key(lod, selected);
                    surfaces.push_back(surface);
                }
            }
        }
        assert(batches(surfaces) == (mode == PASS_MODE_COLOR ? 32 : 2));
    }
    GeometryInstanceSurfaceDataCache a, b;
    assert(a.can_repeat_with(b));
    b.uses_lightmap_specular = true;
    assert(!a.can_repeat_with(b));
    b.uses_lightmap_specular = false;
    b.sort.sort_key2 = 1;
    assert(!a.can_repeat_with(b));
    b.sort.sort_key2 = 0;
    b.sort.sort_key1 = 2;
    assert(!a.can_repeat_with(b));
    std::cout << "PASS: shadow draw-key model 32 to 2 batches, color unchanged\\n";
}
"""
        cpp = cpp.replace("REPEAT_EXPRESSION", repeat_expr)
        cpp = cpp.replace("DEPTH_EXPRESSION", layer_expr)
        with tempfile.TemporaryDirectory(prefix="cgame_shadow_batched_") as temp:
            source = Path(temp) / "shadow.cpp"
            binary = Path(temp) / "shadow"
            source.write_text(cpp, encoding="utf-8")
            compiler = os.environ.get("CXX", "c++")
            subprocess.run(
                [compiler, "-std=c++17", "-O2", "-Wall", "-Wextra", "-Werror",
                 str(source), "-o", str(binary)],
                check=True, timeout=90
            )
            subprocess.run([str(binary)], check=True, timeout=30)


if __name__ == "__main__":
    unittest.main()
