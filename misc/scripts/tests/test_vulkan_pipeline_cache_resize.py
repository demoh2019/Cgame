#!/usr/bin/env python3
"""Isolated native regression test for upstream Godot PR #125598.

Compiles the real pipeline_cache_serialize() method from the checked-out source
against Vulkan and buffer test doubles. This does not require a GPU or Godot.
"""

import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "drivers/vulkan/rendering_device_driver_vulkan.cpp"
METHOD_PATTERN = r"Vector<uint8_t>\s+RenderingDeviceDriverVulkan::pipeline_cache_serialize\(\)\s*\{"


def extract_method():
    source = SOURCE.read_text(encoding="utf-8")
    match = re.search(METHOD_PATTERN, source)
    if not match:
        raise AssertionError("pipeline_cache_serialize() definition not found")
    end = source.find("\n}\n", match.start())
    if end < 0:
        raise AssertionError("pipeline_cache_serialize() closing brace not found")
    return source[match.start() : end + 2]


HARNESS = r"""
#include <algorithm>
#include <cassert>
#include <cstddef>
#include <cstdint>
#include <vector>

using uint8_t = std::uint8_t;

template <typename T>
struct Vector {
    std::vector<T> data;
    void resize(std::size_t n) { data.resize(n); }
    T *ptrw() { return data.data(); }
    const T *ptr() const { return data.data(); }
    std::size_t size() const { return data.size(); }
};

struct PipelineCacheHeader {
    std::size_t data_size = 0;
    std::uint32_t data_hash = 0;
};

enum VkResult { VK_SUCCESS = 0, VK_INCOMPLETE = 1, VK_ERROR = -1 };
std::size_t reported_size = 0;
VkResult reported_status = VK_SUCCESS;

VkResult vkGetPipelineCacheData(int, int, std::size_t *size, uint8_t *data) {
    assert(reported_size <= *size);
    for (std::size_t i = 0; i < reported_size; i++) {
        data[i] = static_cast<uint8_t>(i + 1);
    }
    *size = reported_size;
    return reported_status;
}

std::uint32_t hash_murmur3_buffer(const uint8_t *data, std::size_t size) {
    std::uint32_t hash = 0;
    for (std::size_t i = 0; i < size; i++) {
        hash += data[i];
    }
    return hash;
}

#define DEV_ASSERT(condition) assert(condition)
#define ERR_FAIL_COND_V_MSG(condition, value, message) \
    do { if (condition) { return value; } } while (false)

struct Cache {
    int vk_cache = 1;
    std::size_t current_size = 0;
    Vector<uint8_t> buffer;
};

struct RenderingDeviceDriverVulkan {
    int vk_device = 1;
    Cache pipelines_cache;
    Vector<uint8_t> pipeline_cache_serialize();
};

__METHOD__

int main() {
    for (std::size_t actual_size : {std::size_t(0), std::size_t(1), std::size_t(4), std::size_t(16)}) {
        for (VkResult status : {VK_SUCCESS, VK_INCOMPLETE}) {
            RenderingDeviceDriverVulkan device;
            device.pipelines_cache.current_size = 16;
            reported_size = actual_size;
            reported_status = status;
            const Vector<uint8_t> output = device.pipeline_cache_serialize();
            assert(output.size() == sizeof(PipelineCacheHeader) + actual_size);
            const auto *header = reinterpret_cast<const PipelineCacheHeader *>(output.ptr());
            assert(header->data_size == actual_size);
            std::uint32_t expected_hash = 0;
            for (std::size_t i = 0; i < actual_size; ++i) {
                const uint8_t byte = output.ptr()[sizeof(PipelineCacheHeader) + i];
                assert(byte == i + 1);
                expected_hash += byte;
            }
            assert(header->data_hash == expected_hash);
        }
    }
    RenderingDeviceDriverVulkan failed;
    failed.pipelines_cache.current_size = 16;
    reported_size = 3;
    reported_status = VK_ERROR;
    assert(failed.pipeline_cache_serialize().size() == 0);
}
"""


class PipelineCacheResizeRegression(unittest.TestCase):
    def test_resize_uses_reported_size_after_vulkan_call(self):
        method = extract_method()
        first = method.index("pipelines_cache.buffer.resize(pipelines_cache.current_size + sizeof(PipelineCacheHeader));")
        call = method.index("vkGetPipelineCacheData(")
        second = method.index("pipelines_cache.buffer.resize(pipelines_cache.current_size + sizeof(PipelineCacheHeader));", first + 1)
        header = method.index("PipelineCacheHeader *header =")
        self.assertLess(first, call)
        self.assertLess(call, second)
        self.assertLess(second, header)
        self.assertEqual(method.count("pipelines_cache.buffer.resize("), 2)

    def test_real_method_with_mock_vulkan_sizes(self):
        compiler = os.environ.get("CXX", "c++")
        if not shutil.which(compiler):
            self.skipTest(f"C++ compiler {compiler!r} not installed")
        code = HARNESS.replace("__METHOD__", extract_method())
        with tempfile.TemporaryDirectory(prefix="vulkan-cache-test-") as tmpdir:
            binary = Path(tmpdir) / "pipeline_cache_test"
            built = subprocess.run(
                [compiler, "-std=c++17", "-Wall", "-Wextra", "-Werror",
                 "-x", "c++", "-", "-o", str(binary)],
                input=code, text=True, capture_output=True, check=False,
            )
            self.assertEqual(built.returncode, 0, built.stderr)
            executed = subprocess.run(
                [str(binary)], text=True, capture_output=True, check=False,
            )
            self.assertEqual(executed.returncode, 0, executed.stderr)


if __name__ == "__main__":
    unittest.main()
