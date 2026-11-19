"""Regression tests for Cgame runtime/editor hot-path performance backports.

Behavioral C++ harness compiles the *actual* GDScript notification method using
test doubles. Other tests protect ordering and semantics of source transformations.
These are not FPS or peak-RSS measurements and do not replace a native engine build.
"""

from pathlib import Path
import os
import random
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]


def source(path):
    return (ROOT / path).read_text(encoding="utf-8")


def function(text, signature):
    start = text.index(signature)
    opening = text.index("{", start)
    level = 0
    for i in range(opening, len(text)):
        if text[i] == "{":
            level += 1
        elif text[i] == "}":
            level -= 1
            if level == 0:
                return text[start:i + 1]
    raise AssertionError("Unbalanced function " + signature)


class GDScriptNotificationHotpath(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.body = function(source("modules/gdscript/gdscript.cpp"),
                            "void GDScriptInstance::notification(")

    def test_fast_reversed_chain_does_not_allocate(self):
        self.assertIn("if (p_reversed)", self.body)
        fast = self.body.split("if (p_reversed)", 1)[1].split("return;", 1)[0]
        self.assertIn("sc = sc->base.ptr()", fast)
        self.assertIn("member_functions.getptr(notification_str)", fast)
        self.assertNotIn("push_back(", fast)

    def test_inline_stack_avoids_heap_for_short_chains(self):
        self.assertIn("constexpr uint32_t INLINE_SCRIPT_DEPTH = 8;", self.body)
        self.assertIn("GDScript *inline_stack[INLINE_SCRIPT_DEPTH];", self.body)
        self.assertIn("script_count < INLINE_SCRIPT_DEPTH", self.body)
        self.assertIn("script_count <= INLINE_SCRIPT_DEPTH ? inline_stack : overflow_stack.ptr()", self.body)

    def test_long_inheritance_preserves_overflow_fallback(self):
        self.assertIn("if (script_count == INLINE_SCRIPT_DEPTH)", self.body)
        self.assertIn("overflow_stack.push_back(inline_stack[i]);", self.body)
        self.assertIn("overflow_stack.push_back(sc);", self.body)

    def test_base_first_order_preserved(self):
        self.assertIn("for (uint32_t idx = script_count; idx > 0; idx--)", self.body)
        self.assertIn("GDScript *sc = script_stack[idx - 1];", self.body)

    def test_function_lookup_single_pass(self):
        self.assertEqual(self.body.count("member_functions.getptr(notification_str)"), 2)
        self.assertNotIn("member_functions.find(notification_str)", self.body)

    def test_actual_notification_method_compiles_and_preserves_order(self):
        compiler = shutil.which(os.environ.get("CXX", "g++"))
        if not compiler:
            self.skipTest("C++ compiler unavailable")
        fixture = r'''
#include <vector>
#include <string>
#include <unordered_map>
#include <cstdlib>
using StringName = std::string;
#define likely(x) (x)
#define unlikely(x) (x)
struct Callable { struct CallError { int error = 0; }; };
struct Variant { int value; Variant(int p_value) : value(p_value) {} };
struct GDScriptInstance;
static std::vector<int> calls;
struct GDScriptFunction {
    int number = 0;
    void call(GDScriptInstance *, const Variant *const *args, int count, Callable::CallError &) {
        if (count != 1 || args[0]->value != 42) std::abort();
        calls.push_back(number);
    }
};
template <typename K, typename V> struct HashMap {
    std::unordered_map<K, V> items;
    V *getptr(const K &key) {
        auto it = items.find(key);
        return it == items.end() ? nullptr : &it->second;
    }
};
struct GDScript;
struct ScriptRef {
    GDScript *target = nullptr;
    GDScript *ptr() const { return target; }
    GDScript *operator->() const { return target; }
};
struct GDScript {
    bool valid = true;
    ScriptRef base;
    HashMap<StringName, GDScriptFunction *> member_functions;
};
struct GDScriptLanguage {
    struct { StringName _notification = "_notification"; } strings;
    static GDScriptLanguage *get_singleton() { static GDScriptLanguage singleton; return &singleton; }
};
template <typename T> struct LocalVector {
    std::vector<T> data;
    void push_back(T value) { data.push_back(value); }
    T *ptr() { return data.data(); }
};
struct GDScriptInstance { ScriptRef script; void notification(int p_notification, bool p_reversed); };
'''
        fixture += "\n" + self.body + "\n"
        fixture += r'''
int main() {
    for (int depth : { 1, 2, 7, 8, 9, 12, 32 }) {
        std::vector<GDScript> chain(depth);
        std::vector<GDScriptFunction> methods(depth);
        for (int i = 0; i < depth; ++i) {
            chain[i].base.target = i + 1 < depth ? &chain[i + 1] : nullptr;
            chain[i].valid = (i == 0 || i % 5 != 0);
            methods[i].number = i;
            chain[i].member_functions.items["_notification"] = &methods[i];
        }
        GDScriptInstance instance;
        instance.script.target = &chain[0];
        for (bool reversed : { false, true }) {
            calls.clear();
            instance.notification(42, reversed);
            std::vector<int> expected;
            if (reversed) {
                for (int i = 0; i < depth; ++i) {
                    if (chain[i].valid) expected.push_back(i);
                }
            } else {
                for (int i = depth - 1; i >= 0; --i) {
                    if (chain[i].valid) expected.push_back(i);
                }
            }
            if (calls != expected) return 1;
        }
    }
    return 0;
}
'''
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "notification.cpp"
            binary = Path(tmp) / "notification"
            path.write_text(fixture, encoding="utf-8")
            build = subprocess.run([compiler, "-std=c++17", "-O2", str(path), "-o", str(binary)],
                                   capture_output=True, text=True, check=False, timeout=45)
            self.assertEqual(build.returncode, 0, build.stderr)
            run = subprocess.run([str(binary)], capture_output=True, text=True,
                                 check=False, timeout=10)
            self.assertEqual(run.returncode, 0, run.stderr)


class DirectionalShadowHotpath(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        text = source("servers/rendering/renderer_scene_cull.cpp")
        cls.shadow = text.split("const uint32_t shadow_base_type =", 1)[1].split(
            "#undef HIDDEN_BY_VISIBILITY_CHECKS", 1)[0]

    def test_visibility_checked_once_before_light_loops(self):
        self.assertIn("shadow_count > 0 && VIS_CHECK", self.shadow)
        self.assertLess(self.shadow.index("VIS_CHECK"), self.shadow.index("for (uint32_t j"))

    def test_geometry_and_cast_shadow_checked_before_light_loops(self):
        self.assertLess(self.shadow.index("INSTANCE_GEOMETRY_MASK"), self.shadow.index("for (uint32_t j"))
        self.assertLess(self.shadow.index("FLAG_CAST_SHADOWS"), self.shadow.index("for (uint32_t j"))

    def test_particle_inactivity_test_not_repeated_per_cascade(self):
        self.assertLess(self.shadow.index("particles_is_inactive("), self.shadow.index("for (uint32_t j"))

    def test_layer_mask_checked_before_cascades(self):
        self.assertLess(self.shadow.index("LAYER_CHECK &"), self.shadow.index("for (uint32_t k"))

    def test_frustum_checked_before_expensive_culler(self):
        self.assertLess(self.shadow.index("IN_FRUSTUM("),
                        self.shadow.index("light_culler->cull_directional_light("))

    def test_shadow_predicate_equivalence_under_randomized_inputs(self):
        rng = random.Random(124897)
        old_calls = new_calls = 0
        for _ in range(10000):
            visible, geometry, cast, inactive = (rng.choice((True, False)) for _ in range(4))
            masks = [(rng.getrandbits(8), [(rng.choice((True, False)),
                                             rng.choice((True, False))) for _ in range(4)])
                     for _ in range(rng.randint(0, 4))]
            visible_layers = rng.getrandbits(8)
            old = []
            for j, (mask, cascades) in enumerate(masks):
                for k, (in_frustum, culler_result) in enumerate(cascades):
                    old_calls += 1
                    if (culler_result and in_frustum and visible and geometry
                            and cast and bool(mask & visible_layers) and not inactive):
                        old.append((j, k))
            new = []
            if masks and visible and geometry and cast and not inactive:
                for j, (mask, cascades) in enumerate(masks):
                    if not (mask & visible_layers):
                        continue
                    for k, (in_frustum, culler_result) in enumerate(cascades):
                        if not in_frustum:
                            continue
                        new_calls += 1
                        if culler_result:
                            new.append((j, k))
            self.assertEqual(old, new)
        self.assertLess(new_calls, old_calls)


class AnimationHotpath(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.blend = source("scene/animation/animation_blend_tree.cpp")
        cls.mixer = source("scene/animation/animation_mixer.cpp")
        cls.player = source("scene/animation/animation_player.cpp")
        cls.header = source("scene/animation/animation_player.h")

    def test_blend_tree_setter_uses_one_lookup(self):
        part = function(self.blend, "void AnimationNodeBlendTree::set_node_position(")
        self.assertEqual(part.count("nodes.getptr(p_node)"), 1)
        self.assertNotIn("nodes.has(p_node)", part)

    def test_blend_tree_getter_uses_one_lookup(self):
        part = function(self.blend, "Vector2 AnimationNodeBlendTree::get_node_position(")
        self.assertEqual(part.count("nodes.getptr(p_node)"), 1)
        self.assertNotIn("nodes.has(p_node)", part)

    def test_animation_mixer_does_not_lookup_reset_twice(self):
        part = function(self.mixer, "bool AnimationMixer::_update_caches()")
        self.assertIn("get_animation_or_null(SceneStringName(RESET))", part)
        self.assertNotIn("has_reset_anim", part)

    def test_player_stores_animation_name_without_string_conversion(self):
        self.assertIn("StringName animation_name;", self.header)
        self.assertIn("StringName prev_animation_name = playback.current.animation_name;", self.player)

    def test_player_diagnostics_explicitly_convert_string_name(self):
        self.assertIn("String(playback.current.animation_name)", self.player)


class EditorImportHotpath(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.fs = source("editor/file_system/editor_file_system.cpp")
        cls.dir = source("drivers/unix/dir_access_unix.cpp")
        cls.find_file = function(cls.fs, "bool EditorFileSystem::_find_file(")
        cls.reimport = function(cls.fs, "void EditorFileSystem::reimport_files(")

    def test_res_path_can_skip_localize_path_allocation(self):
        self.assertIn('f.begins_with("res://")', self.find_file)
        self.assertIn("!_is_simple_res_path(f)", self.find_file)

    def test_find_file_does_not_allocate_dir_access_per_lookup(self):
        self.assertNotIn("DirAccess::create(DirAccess::ACCESS_FILESYSTEM)", self.find_file)

    def test_path_comparison_uses_character_spans(self):
        self.assertIn("const Span<char32_t> str = f.span();", self.find_file)
        self.assertIn("_span_equals(", self.find_file)

    def test_path_fastpath_rejects_special_segments(self):
        helper = function(self.fs, "static bool _is_simple_res_path(")
        self.assertIn("seg_len == 0", helper)
        self.assertIn("seg_len == 1", helper)
        self.assertIn("seg_len == 2", helper)

    def test_import_wait_yields_instead_of_busy_spinning(self):
        self.assertIn("imported_sem.try_wait()", self.reimport)
        self.assertIn("OS::get_singleton()->delay_usec(1000);", self.reimport)

    def test_import_progress_reports_actual_batch_file(self):
        self.assertIn("reimport_files[from + imported_count].path.get_file()", self.reimport)
        self.assertNotIn("reimport_files[imported_count].path.get_file()", self.reimport)

    def test_no_redundant_change_dir_in_unix_constructor(self):
        ctor = function(self.dir, "DirAccessUnix::DirAccessUnix()")
        self.assertNotIn("change_dir(current_dir);", ctor)


if __name__ == "__main__":
    unittest.main()
