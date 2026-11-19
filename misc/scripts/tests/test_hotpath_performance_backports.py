"""Regression tests for Godot hot-path perf PRs #125350, #125214, #123033, #111153.

Includes compiled harnesses using the actual production C++ insertion-sort and
audio-preview methods, plus contracts for GraphEdit and GDScript property lists.
These tests validate semantics, not measured frame-rate improvements.
"""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]


def method(src, prefix):
    start = src.index(prefix)
    begin = src.index("{", start)
    level = 0
    for i in range(begin, len(src)):
        if src[i] == "{":
            level += 1
        elif src[i] == "}":
            level -= 1
            if level == 0:
                return src[start:i + 1]
    raise AssertionError("Unbalanced method: " + prefix)


class HotPathTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sort = (ROOT / "core/templates/sort_array.h").read_text()
        cls.graph = (ROOT / "scene/gui/graph_edit.cpp").read_text()
        cls.graph_header = (ROOT / "scene/gui/graph_edit.h").read_text()
        cls.audio = (ROOT / "editor/audio/audio_stream_preview.cpp").read_text()
        cls.gdscript = (ROOT / "modules/gdscript/gdscript.cpp").read_text()

    def test_sort_uses_move_for_elements(self):
        self.assertIn("std::move(p_array[next])", self.sort)
        self.assertIn("std::move(p_array[i - 1])", self.sort)

    def test_sort_no_by_value_unguarded_argument(self):
        self.assertIn("unguarded_linear_insert(int64_t p_last, T *p_array)", self.sort)
        self.assertNotIn("unguarded_linear_insert(int64_t p_last, T p_value", self.sort)

    def test_sort_move_header_explicit(self):
        self.assertIn("#include <utility>", self.sort)

    def test_native_move_only_sort_test(self):
        src = (ROOT / "tests/core/templates/test_sort_array.cpp").read_text()
        self.assertIn("Moving insertion sort works with noncopyable keys", src)
        self.assertIn("MoveKey(const MoveKey &) = delete;", src)

    def test_graph_schedules_only_once(self):
        queue = method(self.graph, "void GraphEdit::_queue_update_top_connection_layer()")
        self.assertIn("if (update_top_connection_layer_queued)", queue)
        self.assertIn("update_top_connection_layer_queued = true;", queue)
        self.assertIn("call_deferred();", queue)

    def test_graph_resets_flag_before_processing(self):
        update = method(self.graph, "void GraphEdit::_update_top_connection_layer()")
        self.assertIn("update_top_connection_layer_queued = false;", update)
        self.assertLess(update.index("update_top_connection_layer_queued = false;"),
                        update.index("_update_scrollbars();"))

    def test_graph_no_direct_deferred_scheduling(self):
        count = self.graph.count(
            "callable_mp(this, &GraphEdit::_update_top_connection_layer).call_deferred();")
        self.assertEqual(count, 1)

    def test_graph_queue_property_and_declaration(self):
        self.assertIn("bool update_top_connection_layer_queued = false;", self.graph_header)
        self.assertIn("void _queue_update_top_connection_layer();", self.graph_header)

    def test_gdscript_property_list_no_extra_list(self):
        prop = method(self.gdscript, "void GDScript::_get_script_property_list(")
        self.assertNotIn("List<PropertyInfo> props;", prop)
        self.assertNotIn("msort.reverse();", prop)

    def test_gdscript_property_list_keeps_sorted_order(self):
        prop = method(self.gdscript, "void GDScript::_get_script_property_list(")
        self.assertIn("msort.sort();", prop)
        self.assertIn("for (const _GDScriptMemberSort &member : msort)", prop)

    def test_audio_min_max_use_first_sample(self):
        self.assertIn("uint8_t vmax = preview[time_from * 2 + 1];", self.audio)
        self.assertIn("uint8_t vmin = preview[time_from * 2];", self.audio)

    def test_audio_min_max_skip_first_after_initializing(self):
        self.assertEqual(self.audio.count("for (int i = time_from + 1; i < time_to; i++)"), 2)

    @unittest.skipUnless(shutil.which("c++"), "C++ compiler unavailable")
    def test_compiled_production_insertion_sort_moves_without_copies(self):
        head = r"""
#include <cstdint>
#include <utility>
struct Value {
    int key;
    static int copies;
    static int moves;
    explicit Value(int x) : key(x) {}
    Value(const Value &x) : key(x.key) { ++copies; }
    Value &operator=(const Value &x) { key = x.key; ++copies; return *this; }
    Value(Value &&x) noexcept : key(x.key) { ++moves; }
    Value &operator=(Value &&x) noexcept { key = x.key; ++moves; return *this; }
};
int Value::copies = 0;
int Value::moves = 0;
struct Less { bool operator()(const Value &a, const Value &b) const { return a.key < b.key; } };
#define ERR_BAD_COMPARE(expr) if (expr) break
struct Harness {
    using T = Value;
    static constexpr bool Validate = false;
    Less compare;
"""
        tail = r"""
};
int main() {
    Harness h;
    Value values[] = {Value(8), Value(4), Value(7), Value(1), Value(2), Value(0)};
    Value::copies = Value::moves = 0;
    h.insertion_sort(0, 6, values);
    if (Value::copies != 0 || Value::moves == 0) return 1;
    for (int i=1; i<6; i++) if (values[i-1].key > values[i].key) return 2;
    return 0;
}
"""
        functions = [method(self.sort, "inline void unguarded_linear_insert("),
                     method(self.sort, "inline void linear_insert("),
                     method(self.sort, "inline void insertion_sort(")]
        self._compile_and_run(head + "\n".join(functions) + tail)

    @unittest.skipUnless(shutil.which("c++"), "C++ compiler unavailable")
    def test_compiled_audio_preview_empty_and_window_bounds(self):
        head = r"""
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <vector>
#define CLAMP(value, min, max) std::clamp((value), (min), (max))
struct AudioStreamPreview {
    float length = 10.0f;
    std::vector<uint8_t> preview;
    float get_max(float, float) const;
    float get_min(float, float) const;
};
"""
        tail = r"""
int main() {
    AudioStreamPreview audio;
    if (audio.get_max(0, 10) != 0 || audio.get_min(0, 10) != 0) return 1;
    audio.preview = {10, 250, 20, 200, 30, 150, 40, 100};
    if (std::fabs(audio.get_max(0, 10) - ((250 / 255.0) * 2.0 - 1.0)) > 0.000001) return 2;
    if (std::fabs(audio.get_min(0, 10) - ((10 / 255.0) * 2.0 - 1.0)) > 0.000001) return 3;
    if (std::fabs(audio.get_max(5, 6) - ((150 / 255.0) * 2.0 - 1.0)) > 0.000001) return 4;
    if (std::fabs(audio.get_min(5, 6) - ((30 / 255.0) * 2.0 - 1.0)) > 0.000001) return 5;
    audio.length = 0;
    if (audio.get_max(0, 10) != 0 || audio.get_min(0, 10) != 0) return 6;
    return 0;
}
"""
        # Exact functions copied from production source, no model reimplementation.
        funcs = [method(self.audio, "float AudioStreamPreview::get_max("),
                 method(self.audio, "float AudioStreamPreview::get_min(")]
        self._compile_and_run(head + "\n".join(funcs) + tail)

    def _compile_and_run(self, source):
        with tempfile.TemporaryDirectory() as folder:
            binary = str(Path(folder) / "regression")
            compiler = subprocess.run(
                ["c++", "-std=c++17", "-O2", "-Wall", "-Wextra", "-Werror",
                 "-x", "c++", "-", "-o", binary],
                input=source, capture_output=True, text=True, check=False,
            )
            self.assertEqual(compiler.returncode, 0, compiler.stderr)
            result = subprocess.run([binary], capture_output=True, text=True, check=False)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
