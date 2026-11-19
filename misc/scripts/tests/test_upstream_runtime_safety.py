#!/usr/bin/env python3
"""Regression contracts for Godot upstream #125472, #125546 and #125451.

This suite compiles real PerfettoScriptTracer and AudioDriverWeb::input_stop
source fragments against minimal C++ doubles, plus checks the TileMap guard.
It does not replace full engine builds or Web/graphics integration tests.
"""
from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def extract_cpp(source: str, signature: str) -> str:
    start = source.index(signature)
    opening = source.index("{", start)
    level = 0
    for pos in range(opening, len(source)):
        if source[pos] == "{":
            level += 1
        elif source[pos] == "}":
            level -= 1
            if level == 0:
                return source[start:pos + 1]
    raise AssertionError("Unbalanced C++ body: " + signature)


def compile_and_run(test: unittest.TestCase, code: str) -> None:
    compiler = shutil.which(os.environ.get("CXX", "c++"))
    if not compiler:
        test.skipTest("No C++ compiler available")
    with tempfile.TemporaryDirectory() as temp:
        source = Path(temp) / "test.cpp"
        executable = Path(temp) / "test"
        source.write_text(code, encoding="utf-8")
        result = subprocess.run(
            [compiler, "-std=c++17", "-Wall", "-Wextra", "-Werror",
             "-Wno-unused-parameter", str(source), "-o", str(executable)],
            capture_output=True, text=True, timeout=30, check=False,
        )
        test.assertEqual(result.returncode, 0, result.stderr)
        run = subprocess.run([str(executable)], capture_output=True, text=True,
                             timeout=10, check=False)
        test.assertEqual(run.returncode, 0, run.stderr)


class PerfettoTracerRegressions(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        text = (ROOT / "core/profiling/profiling.h").read_text(encoding="utf-8")
        cls.definition = extract_cpp(text, "struct PerfettoScriptTracer {") + ";"

    def test_suppressed_traces_never_emit_unpaired_end_events(self) -> None:
        program = r'''
#include <cassert>
#include <set>
#include <string>
struct StringName {
    std::string data;
    StringName(const char *value = "") : data(value) {}
    bool operator<(const StringName &other) const { return data < other.data; }
    const StringName &string() const { return *this; }
    const StringName &utf8() const { return *this; }
    const char *get_data() const { return data.c_str(); }
};
namespace perfetto { struct DynamicString { explicit DynamicString(const char *) {} }; }
static int started = 0, finished = 0;
static thread_local std::set<StringName> __tracing_system_call;
#define _FORCE_INLINE_ inline
#define TRACE_EVENT_BEGIN(...) (++started)
#define TRACE_EVENT_END(...) (++finished)
''' + self.definition + r'''
int main() {
    StringName file("main.gd"), func("_ready"), system("system");
    {
        PerfettoScriptTracer regular(file, func, StringName("normal"), 12, false);
        assert(regular.tracing && started == 1 && finished == 0);
    }
    assert(finished == 1);
    __tracing_system_call.insert(StringName("suppressed"));
    {
        PerfettoScriptTracer skipped(file, func, StringName("suppressed"), 14, false);
        assert(!skipped.tracing);
        assert(started == 1 && finished == 1);
    }
    assert(started == 1 && finished == 1);
    {
        PerfettoScriptTracer forced(file, func, system, 15, true);
        assert(forced.tracing && started == 2 && finished == 1);
        assert(__tracing_system_call.count(system) == 1);
    }
    assert(started == 2 && finished == 2);
    assert(__tracing_system_call.count(system) == 0);
}
'''
        compile_and_run(self, program)

    def test_tracing_flag_initialized(self) -> None:
        self.assertIn("bool tracing = false;", self.definition)
        self.assertLess(self.definition.index("bool tracing = false;"),
                        self.definition.index("if (is_system_call ||"))


class WebAudioInputStopRegressions(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        source = (ROOT / "platform/web/audio_driver_web.cpp").read_text(encoding="utf-8")
        cls.function = extract_cpp(source, "Error AudioDriverWeb::input_stop()")

    def test_stop_resets_buffer_metadata_across_restarts(self) -> None:
        program = r'''
#include <cassert>
#include <vector>
static std::vector<int> calls;
void godot_audio_input_stop() { calls.push_back(1); }
using Error = int;
constexpr int OK = 0;
struct AudioDriverWeb {
    std::vector<int> input_buffer;
    int input_position = 15;
    int input_size = 42;
    void lock() { calls.push_back(2); }
    void unlock() { calls.push_back(3); }
    Error input_stop();
};
''' + self.function + r'''
int main() {
    AudioDriverWeb driver;
    for (int i = 0; i < 3; ++i) {
        driver.input_buffer.assign(64, 1);
        driver.input_position = i + 3;
        driver.input_size = 64;
        assert(driver.input_stop() == OK);
        assert(driver.input_buffer.empty());
        assert(driver.input_position == 0);
        assert(driver.input_size == 0);
        assert(calls.size() == size_t((i + 1) * 3));
        assert(calls[i * 3] == 1 && calls[i * 3 + 1] == 2 && calls[i * 3 + 2] == 3);
    }
}
'''
        compile_and_run(self, program)

    def test_reset_is_protected_by_lock(self) -> None:
        method = self.function
        self.assertLess(method.index("lock();"), method.index("input_buffer.clear();"))
        self.assertLess(method.index("input_buffer.clear();"), method.index("input_position = 0;"))
        self.assertLess(method.index("input_position = 0;"), method.index("input_size = 0;"))
        self.assertLess(method.index("input_size = 0;"), method.index("unlock();"))


class TileMapPreviewRegressions(unittest.TestCase):
    def test_empty_tilemap_is_guarded_before_first_cell_access(self) -> None:
        code = (ROOT / "modules/tilemap/editor/tiles_editor_plugin.cpp").read_text(encoding="utf-8")
        func = extract_cpp(code, "void TilesEditorUtils::_thread()")
        guard = "if (!tile_map_layer->get_tile_map_layer_data().is_empty()) {"
        access = "encompassing_rect.set_position(tile_map_layer->map_to_local(tile_map_layer->get_tile_map_layer_data().begin()->key));"
        self.assertEqual(func.count(access), 1)
        self.assertIn(guard, func)
        start = func.index(guard)
        end = func.index(access)
        self.assertLess(start, end)
        self.assertFalse(func[start + len(guard):end].strip())
        self.assertTrue(func[end + len(access):].lstrip().startswith("}"))


if __name__ == "__main__":
    unittest.main()
