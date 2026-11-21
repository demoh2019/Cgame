"""Source contract for on-demand ObjectDB class diagnostics in Cgame + Albion.

Static checks complement native compilation and headless runtime tests.
"""
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
MOD = ROOT / "modules/objectdb_profiler"
GAME = ROOT / "game/scripts/client"


class TestRuntimeObjectProfilerContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.header = (MOD / "runtime_object_profiler.h").read_text()
        cls.native = (MOD / "runtime_object_profiler.cpp").read_text()
        cls.register = (MOD / "register_types.cpp").read_text()
        cls.helper = (GAME / "object_population_profiler.gd").read_text()
        cls.online = (GAME / "online_main.gd").read_text()
        cls.native_tests = (MOD / "tests/test_runtime_object_profiler.h").read_text()
        cls.game_tests = (ROOT / "game/tests/test_object_population_profiler.gd").read_text()

    def test_debug_module_and_classdb_registration(self):
        self.assertIn("return env.debug_features", (MOD / "config.py").read_text())
        self.assertIn("GDREGISTER_CLASS(ObjectDBRuntimeProfiler)", self.register)
        self.assertIn('#include "tests/test_runtime_object_profiler.h"', self.register)
        self.assertIn("class ObjectDBRuntimeProfiler : public RefCounted", self.header)
        self.assertIn("Dictionary sample_classes(const PackedStringArray &p_class_names) const;", self.header)
        self.assertIn('D_METHOD("sample_classes", "class_names")', self.native)

    def test_one_locked_pass_and_no_retained_game_objects(self):
        self.assertIn("ObjectDB::debug_objects(count_object_class, &census)", self.native)
        self.assertEqual(self.native.count("ObjectDB::debug_objects("), 1)
        body = self.native.split(
            "static void count_object_class(Object *p_object, void *p_context)", 1
        )[1].split("} // namespace", 1)[0]
        self.assertIn("++census->total", body)
        self.assertIn("p_object->get_class_name()", body)
        self.assertIn("census->slots.getptr(", body)
        self.assertIn("census->counts.write[*slot] += 1;", body)
        for unsafe in ("get_instance(", "ObjectDB::get_object_count(", "SceneTree",
                       "RenderingServer", "AudioServer", "serialize("):
            self.assertNotIn(unsafe, body)
        self.assertIn('result["total"] = census.total;', self.native)
        self.assertIn('result["classes"] = classes;', self.native)

    def test_atomic_validation_and_bound(self):
        method = self.native.split(
            "Dictionary ObjectDBRuntimeProfiler::sample_classes(", 1
        )[1]
        self.assertIn("count <= 0 || count > MAX_CLASS_FILTERS", method)
        self.assertIn("constexpr int MAX_CLASS_FILTERS = 32", self.native)
        self.assertIn("class_string.length() > 128", method)
        self.assertIn("class_string != class_string.strip_edges()", method)
        self.assertIn("census.slots.has(name)", method)
        self.assertIn("return invalid;", method)
        self.assertLess(method.index("census.slots.has(name)"),
                        method.index("ObjectDB::debug_objects("))
        self.assertLess(method.index("ObjectDB::debug_objects("),
                        method.index('result["total"] = census.total'))

    def test_live_debug_hotkey_and_explicit_baseline(self):
        self.assertIn('preload("res://scripts/client/object_population_profiler.gd")',
                      self.online)
        self.assertIn("OS.is_debug_build()", self.online)
        self.assertIn("event.ctrl_pressed and event.shift_pressed", self.online)
        self.assertIn("event.keycode == KEY_F10", self.online)
        self.assertIn("_object_population_profiler.sample()", self.online)
        self.assertIn("ObjectPopulationProfiler.format_report(object_sample)", self.online)
        self.assertIn("get_viewport().set_input_as_handled()", self.online)
        self.assertIn('ClassDB.class_exists("ObjectDBRuntimeProfiler")', self.helper)
        self.assertIn('candidate.has_method("sample_classes")', self.helper)
        self.assertIn('PackedStringArray(TRACKED_CLASSES)', self.helper)
        self.assertIn('var had_previous: bool = not _previous.is_empty()', self.helper)
        self.assertIn('_previous = result.duplicate(true)', self.helper)
        self.assertIn("func reset_baseline()", self.helper)
        self.assertNotIn("func _process(", self.helper)
        self.assertNotIn("func _physics_process(", self.helper)

    def test_real_native_and_game_regressions(self):
        self.assertIn("native class census detects object births and releases without retention",
                      self.native_tests)
        self.assertIn("invalid class filters are rejected before ObjectDB scan",
                      self.native_tests)
        self.assertIn("memnew(Node3D)", self.native_tests)
        self.assertIn("memdelete(temporary)", self.native_tests)
        self.assertIn("too_many.resize(32)", self.native_tests)
        self.assertIn("changes[\"Node3D\"], 1", self.game_tests)
        self.assertIn("released[\"MeshInstance3D\"], -1", self.game_tests)
        self.assertIn("temporary_mesh.free()", self.game_tests)
        self.assertIn("Ctrl+Shift+F10", self.game_tests)
        self.assertIn('"res://tests/test_object_population_profiler.gd"',
                      (ROOT / "game/tests/run_all.gd").read_text())

    def test_documentation_and_ci(self):
        xml = ET.parse(MOD / "doc_classes/ObjectDBRuntimeProfiler.xml").getroot()
        self.assertIn("sample_classes", {
            method.get("name") for method in xml.findall("./methods/method")
        })
        notes = (MOD / "README.md").read_text()
        self.assertIn("Ctrl+Shift+F10", notes)
        self.assertIn("Unreal", notes)
        workflow = (ROOT / ".github/workflows/native-objectdb-runtime-profiler.yml").read_text()
        for marker in ("test_runtime_object_profiler_contract.py",
                       'test_object_population_profiler',
                       "*ObjectDBRuntimeProfiler*",
                       "tests=yes module_text_server_fb_enabled=yes"):
            self.assertIn(marker, workflow)


if __name__ == "__main__":
    unittest.main()
