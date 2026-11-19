"""Native C++ and source-flow regressions for texture-streaming feedback hot paths."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "modules/texture_streaming/texture_streaming.cpp"
HEADER = ROOT / "modules/texture_streaming/feedback_buffer_policy.h"


class TextureStreamingFeedbackTests(unittest.TestCase):
    def test_feedback_buffer_growth_policy_compiles_and_handles_boundaries(self):
        compiler = os.environ.get("CXX", "g++")
        if not shutil.which(compiler):
            self.skipTest(f"{compiler} not installed")

        harness = r"""
#include "modules/texture_streaming/feedback_buffer_policy.h"

#include <algorithm>
#include <cassert>
#include <cstdint>
#include <limits>

using namespace TextureStreamingFeedbackPolicy;

int main() {
    static_assert(!needs_resize(4096, true, 0), "idle feedback must reuse a live buffer");
    static_assert(needs_resize(0, false, 0), "first allocation is required");
    static_assert(needs_resize(4096, false, 0), "invalid RID must be recreated");
    static_assert(needs_resize(4095, true, 0), "minimum capacity is 4 KiB");
    static_assert(!needs_resize(4096, true, 1), "one material uses existing capacity");
    static_assert(!needs_resize(4096, true, 1024), "exact boundary fits");
    static_assert(needs_resize(4096, true, 1025), "one beyond boundary grows");
    static_assert(!needs_resize(8192, true, 2048), "second boundary fits");
    static_assert(needs_resize(8192, true, 2049), "second boundary overflows");
    static_assert(needs_resize(UINT32_MAX, true, (1u << 30)), "arithmetic cannot wrap");
    static_assert(MAX_MATERIAL_COUNT == (1u << 29), "maximum count must fit power-of-two rounding");

    // Simulates repeated empty feedback frames; only first frame should allocate.
    unsigned allocations = 0;
    uint32_t capacity = 0;
    for (int frame = 0; frame < 10000; ++frame) {
        if (needs_resize(capacity, allocations > 0, 0)) {
            ++allocations;
            capacity = MIN_BUFFER_SIZE_BYTES;
        }
    }
    assert(allocations == 1);

    // Deterministic property check against the mathematical 64-bit rule.
    uint32_t rng = 0x5a17cdefu;
    for (int i = 0; i < 50000; ++i) {
        rng = rng * 1664525u + 1013904223u;
        const uint32_t count = rng;
        rng = rng * 1664525u + 1013904223u;
        const uint32_t size = rng;
        const bool valid = (rng & 1u) != 0;
        const uint64_t required = std::max<uint64_t>(MIN_BUFFER_SIZE_BYTES, uint64_t(count) * 4u);
        const bool expected = !valid || uint64_t(size) < required;
        assert(needs_resize(size, valid, count) == expected);
    }
}
"""
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "feedback_policy_test.cpp"
            binary = Path(directory) / "feedback_policy_test"
            source.write_text(harness, encoding="utf-8")
            compiled = subprocess.run(
                [compiler, "-std=c++17", "-O2", "-Wall", "-Wextra", "-Werror",
                 "-pedantic", "-I", str(ROOT), str(source), "-o", str(binary)],
                capture_output=True, text=True, timeout=45,
            )
            self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
            result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_production_reuses_empty_feedback_buffer(self):
        src = SOURCE.read_text(encoding="utf-8")
        resize = src.split("void TextureStreaming::MaterialFeedbackBuffer::resize() {", 1)[1].split(
            "TextureStreaming::MaterialFeedbackBuffer::MaterialFeedbackBuffer()", 1
        )[0]
        self.assertIn("TextureStreamingFeedbackPolicy::needs_resize(buffer_size, buffer.is_valid(), material_info_count)", resize)
        self.assertIn("MAX_MATERIAL_COUNT", resize)
        self.assertNotIn("material_info_count_bytes > 0", resize)

    def test_readback_does_not_trigger_copy_on_write(self):
        src = SOURCE.read_text(encoding="utf-8")
        readback = src.split("void TextureStreaming::_process_material_feedback_buffer(", 1)[1].split(
            "void TextureStreaming::_feedback_buffer_thread_func(", 1
        )[0]
        self.assertIn("p_mb->data.ptr()", readback)
        self.assertNotIn("p_mb->data.ptrw()", readback)
        self.assertIn("const uint32_t *p_data", readback)

    def test_global_lod_constraints_are_read_once_per_feedback_batch(self):
        src = SOURCE.read_text(encoding="utf-8")
        process = src.split("void TextureStreaming::_feedback_buffer_process(", 1)[1].split(
            "void TextureStreaming::_texture_reload_thread_func(", 1
        )[0]
        loop = process.index("for (uint32_t i = 0; i < buffers.size(); i++)")
        self.assertEqual(process.count("_get_system_min_lod()"), 1)
        self.assertEqual(process.count("_get_system_max_lod()"), 1)
        self.assertLess(process.index("_get_system_min_lod()"), loop)
        self.assertLess(process.index("_get_system_max_lod()"), loop)
        self.assertIn("MAX(system_min_lod, configured_max_lod)", process)


if __name__ == "__main__":
    unittest.main()
