#!/usr/bin/env python3
"""Focused C++ execution regressions for Godot upstream PRs #125598 and #125620.

Extracts the actual C++ methods/branches from the engine source, compiles them
against minimal deterministic test doubles, and verifies affected failure paths.
These tests complement rather than replace the full Godot/renderer CI builds.
"""

from __future__ import annotations

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(os.environ.get("GODOT_BACKPORT_ROOT", Path(__file__).resolve().parents[3]))
VULKAN_FILE = ROOT / "drivers/vulkan/rendering_device_driver_vulkan.cpp"
MAIN_FILE = ROOT / "main/main.cpp"


def extract_block(source: str, anchor: str) -> str:
    """Extract a brace-delimited C++ method/block at the unique source anchor."""
    assert source.count(anchor) == 1, f"Expected exactly one {anchor!r}"
    begin = source.index(anchor)
    opening = source.index("{", begin)
    level = 0
    for index in range(opening, len(source)):
        char = source[index]
        if char == "{":
            level += 1
        if char == "}":
            level -= 1
            if level == 0:
                return source[begin : index + 1]
    raise ValueError(f"Unbalanced braces after {anchor}")


def compile_and_run(code: str, extra_flags: tuple[str, ...] = ()) -> str:
    compiler = shutil.which("g++") or shutil.which("clang++") or shutil.which("c++")
    if not compiler:
        raise unittest.SkipTest("A C++ compiler is required for the runtime harness")
    with tempfile.TemporaryDirectory() as temp:
        source = Path(temp) / "regression.cpp"
        program = Path(temp) / "regression"
        source.write_text(code, encoding="utf-8")
        compile_process = subprocess.run(
            [compiler, "-std=c++17", "-Wall", "-Wextra", "-Werror", *extra_flags,
             str(source), "-o", str(program)], capture_output=True, text=True, check=False,
        )
        if compile_process.returncode:
            raise AssertionError(f"Compilation failed:\n{compile_process.stderr}")
        result = subprocess.run([str(program)], capture_output=True, text=True, check=False)
        if result.returncode:
            raise AssertionError(f"Harness exited {result.returncode}: {result.stdout}\n{result.stderr}")
        return result.stdout


VULKAN_STUB = r'''
#include <cassert>
#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <string>
#include <vector>
using VkResult = int;
constexpr VkResult VK_SUCCESS = 0;
constexpr VkResult VK_INCOMPLETE = 5;
constexpr VkResult VK_ERROR = -1;

template<typename T> struct Vector {
    std::vector<T> storage;
    void resize(size_t value) { storage.resize(value); }
    T *ptrw() { return storage.data(); }
    const T *ptr() const { return storage.data(); }
    size_t size() const { return storage.size(); }
};
struct PipelineCacheHeader { size_t data_size = 0; uint64_t data_hash = 0; };
static std::vector<uint8_t> gpu_data;
static VkResult simulated_result = VK_SUCCESS;
static size_t calls = 0;
static VkResult vkGetPipelineCacheData(int, int, size_t *capacity, void *destination) {
    ++calls;
    const size_t copied = std::min(*capacity, gpu_data.size());
    if (copied) { std::memcpy(destination, gpu_data.data(), copied); }
    *capacity = copied;
    return simulated_result == VK_ERROR ? VK_ERROR :
           (simulated_result == VK_INCOMPLETE ? VK_INCOMPLETE :
           (copied < gpu_data.size() ? VK_INCOMPLETE : VK_SUCCESS));
}
static uint64_t hash_murmur3_buffer(const uint8_t *data, size_t size) {
    uint64_t value = 2166136261u;
    for (size_t index = 0; index < size; ++index) { value = (value ^ data[index]) * 16777619u; }
    return value;
}
static std::string vformat(const char *, VkResult) { return "error"; }
#define DEV_ASSERT(condition) assert(condition)
#define ERR_FAIL_COND_V_MSG(condition, retval, text) do { if (condition) { (void)(text); return retval; } } while (0)
struct RenderingDeviceDriverVulkan {
    struct Cache { int vk_cache = 1; size_t current_size = 0; Vector<uint8_t> buffer; } pipelines_cache;
    int vk_device = 0;
    Vector<uint8_t> pipeline_cache_serialize();
};
'''

VULKAN_CHECKS = r'''
static int count = 0;
#define CHECK(expression) do { if (!(expression)) { std::cerr << "Failed: " #expression << " at " << __LINE__ << "\n"; return 1; } ++count; } while (0)
int main() {
    RenderingDeviceDriverVulkan driver;
    auto exercise = [&](size_t requested, std::vector<uint8_t> returned, VkResult result) {
        driver.pipelines_cache.current_size = requested;
        gpu_data = returned;
        simulated_result = result;
        return driver.pipeline_cache_serialize();
    };
    auto shrunk = exercise(128, {1, 2, 3}, VK_SUCCESS);
    CHECK(shrunk.size() == sizeof(PipelineCacheHeader) + 3);
    auto *header = reinterpret_cast<const PipelineCacheHeader *>(shrunk.ptr());
    CHECK(header->data_size == 3);
    CHECK(header->data_hash == hash_murmur3_buffer(shrunk.ptr() + sizeof(PipelineCacheHeader), 3));
    CHECK(std::memcmp(shrunk.ptr() + sizeof(PipelineCacheHeader), gpu_data.data(), 3) == 0);

    auto exact = exercise(4, {11, 12, 13, 14}, VK_SUCCESS);
    CHECK(exact.size() == sizeof(PipelineCacheHeader) + 4);
    CHECK(reinterpret_cast<const PipelineCacheHeader *>(exact.ptr())->data_size == 4);

    auto empty = exercise(16, {}, VK_SUCCESS);
    CHECK(empty.size() == sizeof(PipelineCacheHeader));
    CHECK(reinterpret_cast<const PipelineCacheHeader *>(empty.ptr())->data_size == 0);

    auto incomplete = exercise(2, {1, 2, 3, 4}, VK_INCOMPLETE);
    CHECK(incomplete.size() == sizeof(PipelineCacheHeader) + 2);
    CHECK(reinterpret_cast<const PipelineCacheHeader *>(incomplete.ptr())->data_size == 2);
    CHECK(incomplete.ptr()[sizeof(PipelineCacheHeader) + 1] == 2);

    auto bad = exercise(4, {1, 2}, VK_ERROR);
    CHECK(bad.size() == 0);
    CHECK(calls == 5);
    std::cout << count << " Vulkan assertions passed\n";
}
'''

MAIN_STUB = r'''
#include <cassert>
#include <iostream>
#include <string>
#include <vector>
static std::vector<std::string> events;
enum Error { OK = 0, ERR_FAIL = 5 };
static int *display_server = nullptr;
static int *input = nullptr;
static int *tsman = nullptr;
static void finalize_display() { events.emplace_back("display"); display_server = nullptr; }
struct NavigationServer2DManager { static void finalize_server_manager() { events.emplace_back("nav2d"); } };
struct NavigationServer3DManager { static void finalize_server_manager() { events.emplace_back("nav3d"); } };
struct PhysicsServer2DManager { static void finalize_server_manager() { events.emplace_back("phys2d"); } };
struct PhysicsServer3DManager { static void finalize_server_manager() { events.emplace_back("phys3d"); } };
struct GDExtension { static const int INITIALIZATION_LEVEL_SERVERS = 1; };
struct GDExtensionManager {
    static GDExtensionManager *get_singleton() { static GDExtensionManager instance; return &instance; }
    void deinitialize_extensions(int) { events.emplace_back("extensions"); }
};
constexpr int MODULE_INITIALIZATION_LEVEL_SERVERS = 1;
static void uninitialize_modules(int) { events.emplace_back("modules"); }
static void unregister_server_types() { events.emplace_back("servertypes"); }
#define ERR_PRINT(message) do { (void)message; events.emplace_back("error"); } while (0)
#define memdelete(ptr) do { events.emplace_back("delete"); (ptr) = nullptr; } while (0)
static Error simulate(Error err, bool have_display) {
    display_server = have_display ? reinterpret_cast<int *>(1) : nullptr;
    input = reinterpret_cast<int *>(1);
    tsman = reinterpret_cast<int *>(1);
'''

MAIN_CHECKS = r'''
    return OK;
}
static int assertions = 0;
#define CHECK(condition) do { if (!(condition)) { std::cerr << "Failed: " #condition "\n"; return 1; } ++assertions; } while(0)
int main() {
    events.clear();
    CHECK(simulate(ERR_FAIL, false) == ERR_FAIL);
    CHECK(!events.empty());
    CHECK(events[0] == "error");
    CHECK(events[1] == "display");
    const auto extensions = std::find(events.begin(), events.end(), "extensions");
    CHECK(extensions != events.end());
#ifndef NAVIGATION_2D_DISABLED
    const auto nav2d = std::find(events.begin(), events.end(), "nav2d");
    CHECK(nav2d != events.end());
    CHECK(nav2d < extensions);
#else
    CHECK(std::find(events.begin(), events.end(), "nav2d") == events.end());
#endif
#ifndef NAVIGATION_3D_DISABLED
    const auto nav3d = std::find(events.begin(), events.end(), "nav3d");
    CHECK(nav3d != events.end());
    CHECK(nav3d < extensions);
#else
    CHECK(std::find(events.begin(), events.end(), "nav3d") == events.end());
#endif
    CHECK(std::find(events.begin(), events.end(), "modules") > extensions);
    CHECK(std::find(events.begin(), events.end(), "servertypes") > extensions);
    CHECK(std::find(events.begin(), events.end(), "phys2d") != events.end());
    CHECK(std::find(events.begin(), events.end(), "phys3d") != events.end());
    CHECK(display_server == nullptr);
    CHECK(input == nullptr);
    CHECK(tsman == nullptr);
    events.clear();
    CHECK(simulate(OK, true) == OK);
    CHECK(events.empty());
    std::cout << assertions << " startup assertions passed\n";
}
'''


class VulkanCacheBackportTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.method = extract_block(
            VULKAN_FILE.read_text(encoding="utf-8"),
            "Vector<uint8_t> RenderingDeviceDriverVulkan::pipeline_cache_serialize()",
        )

    def test_resize_after_gpu_reports_actual_size(self):
        marker = "pipelines_cache.buffer.resize(pipelines_cache.current_size + sizeof(PipelineCacheHeader));"
        request = "vkGetPipelineCacheData(vk_device, pipelines_cache.vk_cache"
        self.assertEqual(self.method.count(marker), 2)
        self.assertLess(self.method.index(marker), self.method.index(request))
        self.assertGreater(self.method.rindex(marker), self.method.index(request))

    def test_resize_follows_vulkan_error_check(self):
        self.assertGreater(self.method.rindex("pipelines_cache.buffer.resize"),
                           self.method.index("ERR_FAIL_COND_V_MSG"))

    def test_header_hash_follows_final_resize(self):
        self.assertLess(self.method.rindex("pipelines_cache.buffer.resize"),
                        self.method.index("header->data_hash"))

    def test_real_vulkan_serialization_cpp_branch(self):
        output = compile_and_run(VULKAN_STUB + "\n" + self.method + "\n" + VULKAN_CHECKS)
        self.assertIn("Vulkan assertions passed", output)


class StartupFailureBackportTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.method = extract_block(
            MAIN_FILE.read_text(encoding="utf-8"),
            "if (err != OK || display_server == nullptr) {\n\t\t\tERR_PRINT(\"Unable to create DisplayServer",
        )

    def test_cleanup_display_first(self):
        self.assertIn("finalize_display();", self.method)
        self.assertLess(self.method.index("finalize_display();"), self.method.index("uninitialize_modules("))
        self.assertNotIn("memdelete(display_server)", self.method)

    def test_navigation_cleanup_precedes_server_deinit(self):
        for manager in ("NavigationServer2DManager", "NavigationServer3DManager"):
            self.assertIn(f"{manager}::finalize_server_manager();", self.method)
            self.assertLess(self.method.index(f"{manager}::finalize_server_manager();"),
                            self.method.index("deinitialize_extensions("))

    def test_navigation_compile_guards_present(self):
        self.assertIn("#ifndef NAVIGATION_2D_DISABLED", self.method)
        self.assertIn("#ifndef NAVIGATION_3D_DISABLED", self.method)
        self.assertIn("#endif // NAVIGATION_2D_DISABLED", self.method)
        self.assertIn("#endif // NAVIGATION_3D_DISABLED", self.method)

    def test_real_startup_failure_branch_cpp(self):
        output = compile_and_run(MAIN_STUB.replace("#include <cassert>", "#include <cassert>\n#include <algorithm>") + "\n" + self.method + "\n" + MAIN_CHECKS)
        self.assertIn("startup assertions passed", output)

    def test_navigation_disabled_configuration_cpp(self):
        output = compile_and_run(MAIN_STUB.replace("#include <cassert>", "#include <cassert>\n#include <algorithm>") + "\n" + self.method + "\n" + MAIN_CHECKS,
            extra_flags=("-DNAVIGATION_2D_DISABLED", "-DNAVIGATION_3D_DISABLED"))
        self.assertIn("startup assertions passed", output)


if __name__ == "__main__":
    unittest.main()
