#!/usr/bin/env python3
"""Regressions for upstream Godot #125525, #125599 and #125547.

Source contracts plus isolated C++ tests of the exact changed expressions.
A full Godot build and real X11/Vulkan driver tests are separate checks.
"""
from __future__ import annotations

import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


def run_cpp(test, src):
    compiler = shutil.which(os.environ.get("CXX", "c++"))
    if not compiler:
        test.skipTest("C++ compiler unavailable")
    with tempfile.TemporaryDirectory() as folder:
        path = Path(folder)
        cpp = path / "regression.cpp"
        exe = path / "regression"
        cpp.write_text(src, encoding="utf-8")
        build = subprocess.run(
            [compiler, "-std=c++17", "-Wall", "-Wextra", "-Werror",
             str(cpp), "-o", str(exe)],
            capture_output=True, text=True, timeout=35, check=False,
        )
        test.assertEqual(build.returncode, 0, build.stderr)
        run = subprocess.run([str(exe)], capture_output=True,
                             text=True, timeout=10, check=False)
        test.assertEqual(run.returncode, 0, run.stderr)


class BasisSafety(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.importer = read("editor/import/resource_importer_texture.cpp")
        cls.header = read("scene/resources/compressed_texture.h")
        cls.compressed = read("scene/resources/compressed_texture.cpp")
        cls.portable = read("scene/resources/portable_compressed_texture.cpp")

    def test_bit_position_and_renamed_flag_are_consistent(self):
        self.assertRegex(self.header, r"FORMAT_BIT_DETECT_ROUGHNESS\s*=\s*1\s*<<\s*27")
        self.assertIn("CompressedTexture2D::FORMAT_BIT_DETECT_ROUGHNESS", self.importer)
        self.assertIn("FORMAT_BIT_DETECT_ROUGHNESS", self.compressed)
        for part in (self.header, self.importer, self.compressed):
            self.assertNotIn("FORMAT_BIT_DETECT_ROUGNESS", part)

    def test_ctex_decoder_guard_precedes_read_and_decode(self):
        start = self.compressed.index("} else if (data_format == DATA_FORMAT_BASIS_UNIVERSAL) {")
        body = self.compressed[start:self.compressed.index("} else if (data_format == DATA_FORMAT_IMAGE)", start)]
        guard = "ERR_FAIL_NULL_V_MSG(Image::basis_universal_unpacker, Ref<Image>()"
        self.assertIn(guard, body)
        self.assertLess(body.index(guard), body.index("uint32_t size = f->get_32();"))
        self.assertLess(body.index(guard), body.index("Image::basis_universal_unpacker(pv)"))
        self.assertIn("img.is_null() || img->is_empty()", body)

    def test_portable_decoder_guard_and_result_validation(self):
        body = self.portable[self.portable.index("case COMPRESSION_MODE_BASIS_UNIVERSAL: {"):]
        body = body[:body.index("case COMPRESSION_MODE_S3TC:")]
        guard = "ERR_FAIL_NULL_MSG(Image::basis_universal_unpacker_ptr"
        self.assertIn(guard, body)
        self.assertLess(body.index(guard), body.index("Image::basis_universal_unpacker_ptr(data, data_size)"))
        self.assertLess(body.index("ERR_FAIL_COND(image.is_null());"), body.index("image->get_format()"))

    def test_portable_encoding_checks_basis_backend(self):
        start = self.portable.index("void PortableCompressedTexture2D::create_from_image(")
        body = self.portable[start:]
        self.assertIn('ERR_FAIL_NULL_MSG(Image::basis_universal_unpacker, "Basis Universal support is disabled in this build.");', body)


class X11WheelFiltering(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.x11 = read("platform/linuxbsd/x11/display_server_x11.cpp")
        needle = re.search(
            r"if \((mb->get_button_index\(\) < MouseButton::WHEEL_UP"
            r" \|\| mb->get_button_index\(\) > MouseButton::WHEEL_RIGHT)\) \{",
            cls.x11,
        )
        if needle is None:
            raise AssertionError("X11 wheel guard missing")
        cls.predicate = needle.group(1)
        cls.block = cls.x11[needle.start():needle.start() + 1250]

    def test_guard_comes_before_double_click_detection(self):
        self.assertLess(self.block.index("WHEEL_RIGHT"), self.block.index("uint64_t diff ="))
        self.assertLess(self.block.index("WHEEL_RIGHT"), self.block.index("set_double_click(true);"))

    def test_compile_actual_predicate_with_wheel_and_button_cases(self):
        cpp = r'''
#include <cassert>
enum class MouseButton { NONE = 0, LEFT = 1, RIGHT = 2, MIDDLE = 3,
  WHEEL_UP = 4, WHEEL_DOWN = 5, WHEEL_LEFT = 6, WHEEL_RIGHT = 7,
  XBUTTON1 = 8, XBUTTON2 = 9 };
struct Event {
  MouseButton value;
  MouseButton get_button_index() const { return value; }
};
int main() {
  for (int i = 0; i < 10; ++i) {
    Event event{static_cast<MouseButton>(i)};
    Event *mb = &event;
    const bool result = (''' + self.predicate + r''');
    assert(result == (i < 4 || i > 7));
  }
}
'''
        run_cpp(self, cpp)


class VulkanMemoryTracking(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.context = read("drivers/vulkan/rendering_context_driver_vulkan.cpp")
        cls.driver = read("drivers/vulkan/rendering_device_driver_vulkan.cpp")

    def test_memory_table_is_guarded_by_mutex(self):
        self.assertIn('#include "core/os/mutex.h"', self.context)
        self.assertEqual(self.context.count("Mutex memory_report_mutex;"), 1)
        start = self.context.index("void RenderingContextDriverVulkan::memory_report_callback(")
        block = self.context[start:self.context.index("\n}\n", start)]
        self.assertLess(block.index("if (!p_callback_data)"),
                        block.index("MutexLock lock(memory_report_mutex);"))
        self.assertLess(block.index("MutexLock lock(memory_report_mutex);"),
                        block.index("memory_report_table.has(obj_id)"))

    def test_compile_actual_bounded_realloc_copy_expression(self):
        match = re.search(
            r"Memory::realloc_aligned_static\(header, size \+ alignment, "
            r"(MIN\(header->size, size\) \+ alignment), alignment\)",
            self.context,
        )
        self.assertIsNotNone(match)
        cpp = r'''
#include <cassert>
#include <algorithm>
#include <cstddef>
#define MIN(a,b) std::min((a),(b))
struct Header { size_t size; };
int main() {
  for (size_t old_size : {size_t(0), size_t(1), size_t(8), size_t(64), size_t(4096)}) {
    for (size_t size : {size_t(0), size_t(1), size_t(8), size_t(1024)}) {
      for (size_t alignment : {size_t(8), size_t(16), size_t(64)}) {
        Header old{old_size}; Header *header = &old;
        size_t actual = ''' + match.group(1) + r''';
        assert(actual == std::min(old_size, size) + alignment);
        assert(actual <= old_size + alignment);
        assert(actual <= size + alignment);
      }
    }
  }
}
'''
        run_cpp(self, cpp)

    def test_compile_persistent_buffer_host_visible_requirements(self):
        begin = self.driver.index("if (p_usage.has_flag(BUFFER_USAGE_DYNAMIC_PERSISTENT_BIT)) {")
        marker = "alloc_create_info.preferredFlags = VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT;"
        block = self.driver[begin:self.driver.index(marker, begin) + len(marker)]
        self.assertIn("alloc_create_info.requiredFlags |= VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT;", block)
        cpp = r'''
#include <cassert>
#include <initializer_list>
struct Usage { bool persistent; bool has_flag(int) const { return persistent; } };
constexpr int BUFFER_USAGE_DYNAMIC_PERSISTENT_BIT = 1;
constexpr int VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT = 2;
constexpr int VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT = 4;
constexpr int VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT = 8;
struct Allocation { int flags = 0; int requiredFlags = 0; int preferredFlags = 0; };
int main() {
  for (bool persistent : {false, true}) {
    Usage p_usage{persistent}; Allocation alloc_create_info;
''' + block + r'''
    assert(bool(alloc_create_info.flags & 2) == persistent);
    assert(bool(alloc_create_info.requiredFlags & 4) == persistent);
    assert(alloc_create_info.preferredFlags == 8);
  }
}
'''
        run_cpp(self, cpp)


if __name__ == "__main__":
    unittest.main()
