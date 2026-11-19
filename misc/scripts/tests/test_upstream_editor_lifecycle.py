#!/usr/bin/env python3
"""Focused C++ regressions for Godot upstream PRs #125621 and #125502.

Compile actual engine snippets against small C++ mocks to exercise initialization
levels and anchor/offset calculations. The upstream doctests still require a
full Godot build; these tests do not replace them.
"""
from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(os.environ["CGAME_SOURCE_ROOT"]) if "CGAME_SOURCE_ROOT" in os.environ else Path(__file__).resolve().parents[3]


def cpp_function(path: str, signature: str) -> str:
    source = (ROOT / path).read_text(encoding="utf-8")
    start = source.index(signature)
    opening = source.index("{", start)
    depth = 0
    for pos in range(opening, len(source)):
        if source[pos] == "{":
            depth += 1
        elif source[pos] == "}":
            depth -= 1
            if depth == 0:
                return source[start : pos + 1]
    raise AssertionError(f"C++ body not balanced: {path} {signature}")


def compile_and_run(test: unittest.TestCase, code: str, *defines: str) -> None:
    compiler = shutil.which(os.environ.get("CXX", "c++"))
    if compiler is None:
        test.skipTest("No C++ compiler available")
    with tempfile.TemporaryDirectory() as folder:
        path = Path(folder)
        src, exe = path / "case.cpp", path / "case"
        src.write_text(code, encoding="utf-8")
        cmd = [compiler, "-std=c++17", "-Wall", "-Wextra", "-Werror", *("-D" + d for d in defines), str(src), "-o", str(exe)]
        build = subprocess.run(cmd, capture_output=True, text=True, timeout=30, check=False)
        test.assertEqual(build.returncode, 0, build.stderr)
        run = subprocess.run([str(exe)], capture_output=True, text=True, timeout=10, check=False)
        test.assertEqual(run.returncode, 0, run.stderr)


class GDScriptShutdownStageTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        code = cpp_function("modules/gdscript/register_types.cpp", "void uninitialize_gdscript_module(")
        start = code.index("#ifdef TOOLS_ENABLED")
        end = code.index("#endif // TOOLS_ENABLED", start) + len("#endif // TOOLS_ENABLED")
        cls.tools_cleanup = code[start:end]

    def test_parser_cleanup_occurs_only_at_servers_level(self) -> None:
        program = r'''
#include <cassert>
enum ModuleInitializationLevel { MODULE_INITIALIZATION_LEVEL_CORE, MODULE_INITIALIZATION_LEVEL_SERVERS, MODULE_INITIALIZATION_LEVEL_EDITOR };
int removed = 0, unrefed = 0, deleted = 0;
struct Plugin { void unref() { ++unrefed; } } gdscript_translation_parser_plugin;
struct EditorTranslationParser {
    enum Priority { STANDARD };
    static EditorTranslationParser *get_singleton() { static EditorTranslationParser x; return &x; }
    void remove_parser(Plugin &, Priority) { ++removed; }
};
struct GDScriptLanguageProtocol { static GDScriptLanguageProtocol *get_singleton() { return nullptr; } };
struct GDScriptEditorLanguage { static GDScriptEditorLanguage *get_singleton() { return nullptr; } };
#define memdelete(p) (++deleted)
void cleanup(ModuleInitializationLevel p_level) {
    (void)p_level;
''' + self.tools_cleanup + r'''
}
int main() {
    cleanup(MODULE_INITIALIZATION_LEVEL_CORE);
    assert(removed == 0 && unrefed == 0 && deleted == 0);
    cleanup(MODULE_INITIALIZATION_LEVEL_EDITOR);
#ifdef TOOLS_ENABLED
#ifdef GDSCRIPT_NO_LSP
    assert(deleted == 1);
#else
    assert(deleted == 2);
#endif
#else
    assert(deleted == 0);
#endif
    assert(removed == 0 && unrefed == 0);
    cleanup(MODULE_INITIALIZATION_LEVEL_SERVERS);
#ifdef TOOLS_ENABLED
    assert(removed == 1 && unrefed == 1);
#else
    assert(removed == 0 && unrefed == 0);
#endif
}
'''
        for flags in ((), ("TOOLS_ENABLED",), ("TOOLS_ENABLED", "GDSCRIPT_NO_LSP")):
            with self.subTest(defines=flags):
                compile_and_run(self, program, *flags)


class ControlLayoutPositionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.method = cpp_function("scene/gui/control.cpp", "void Control::set_position(")

    def test_position_uses_preconstraint_anchor_layout_in_cpp(self) -> None:
        program = r'''
#include <cassert>
#include <cmath>
#include <initializer_list>
struct Size2 { double x, y; constexpr Size2(double a = 0, double b = 0) : x(a), y(b) {} };
using Point2 = Size2;
struct Rect2 { Point2 position; Size2 size; Rect2(Point2 p, Size2 s) : position(p), size(s) {} };
enum { SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM };
struct LayoutData {
    double anchor[4] = {};
    double offset[4] = {};
    Size2 size_cache = {9999, 8888};
};
struct Control {
    LayoutData data;
    Size2 parent_size = {0, 0};
    Rect2 seen = {{0, 0}, {0, 0}};
    bool kept = false;
    int resized = 0;
    Rect2 get_parent_anchorable_rect() const { return {{0, 0}, parent_size}; }
    void _compute_layout_rect(const Rect2 &r, bool keep) { seen = r; kept = keep; }
    void _size_changed() { ++resized; }
    void set_position(const Point2 &p, bool keep);
};
#define ERR_MAIN_THREAD_GUARD ((void)0)
''' + self.method + r'''
int main() {
    int assertions = 0;
    for (int parent = 0; parent < 4; ++parent) {
        for (int anchor = 0; anchor < 4; ++anchor) {
            for (int offset = 0; offset < 4; ++offset) {
                for (bool keep : {false, true}) {
                    Control c;
                    c.parent_size = {double(parent * 150), double(parent * 60)};
                    c.data.anchor[SIDE_LEFT] = anchor * 0.1;
                    c.data.anchor[SIDE_RIGHT] = anchor * 0.2 + 0.15;
                    c.data.anchor[SIDE_TOP] = anchor * 0.05;
                    c.data.anchor[SIDE_BOTTOM] = anchor * 0.23 + 0.2;
                    c.data.offset[SIDE_LEFT] = -offset * 7.0;
                    c.data.offset[SIDE_RIGHT] = offset * 13.0 + 60;
                    c.data.offset[SIDE_TOP] = -offset * 4.0;
                    c.data.offset[SIDE_BOTTOM] = offset * 9.0 + 30;
                    auto expected_x = c.data.offset[SIDE_RIGHT] - c.data.offset[SIDE_LEFT] +
                        c.parent_size.x * (c.data.anchor[SIDE_RIGHT] - c.data.anchor[SIDE_LEFT]);
                    auto expected_y = c.data.offset[SIDE_BOTTOM] - c.data.offset[SIDE_TOP] +
                        c.parent_size.y * (c.data.anchor[SIDE_BOTTOM] - c.data.anchor[SIDE_TOP]);
                    c.set_position({17, 19}, keep);
                    assert(std::abs(c.seen.size.x - expected_x) < 1e-9);
                    assert(std::abs(c.seen.size.y - expected_y) < 1e-9);
                    assert(c.seen.position.x == 17 && c.seen.position.y == 19);
                    assert(c.kept == keep && c.resized == 1);
                    assertions += 4;
                }
            }
        }
    }
    assert(assertions == 512);
}
'''
        compile_and_run(self, program)


if __name__ == "__main__":
    unittest.main()
