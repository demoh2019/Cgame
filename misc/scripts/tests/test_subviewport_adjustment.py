"""Regressions for upstream Godot #71227 and native SubViewport adjustment tests."""

import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from xml.etree import ElementTree

ROOT = Path(__file__).resolve().parents[3]


def _method(source, signature):
    start = source.index(signature)
    brace = source.index("{", start)
    level = 0
    for i in range(brace, len(source)):
        level += (source[i] == "{") - (source[i] == "}")
        if not level:
            return source[start:i + 1]
    raise AssertionError(signature)


class SubViewportAdjustmentTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cpp = (ROOT / "scene/gui/subviewport_container.cpp").read_text()
        cls.h = (ROOT / "scene/gui/subviewport_container.h").read_text()
        cls.viewport = (ROOT / "scene/main/viewport.cpp").read_text()
        cls.docs = ElementTree.parse(ROOT / "doc/classes/SubViewportContainer.xml").getroot()
        cls.setter = _method(cls.cpp, "void SubViewportContainer::set_adjust_viewport_properties(")
        cls.getter = _method(cls.cpp, "bool SubViewportContainer::is_adjust_viewport_properties_enabled()")
        cls.queue = _method(cls.cpp, "void SubViewportContainer::_queue_adjust_viewport_properties()")
        cls.adjust = _method(cls.cpp, "void SubViewportContainer::_adjust_viewport_properties()")

    def test_backward_compatible_default(self):
        self.assertIn("bool adjust_viewport_properties = true;", self.h)

    def test_accessors_declared(self):
        self.assertIn("void set_adjust_viewport_properties(bool", self.h)
        self.assertIn("bool is_adjust_viewport_properties_enabled() const;", self.h)

    def test_state_transition_queues_only_enabling(self):
        self.assertIn("if (adjust_viewport_properties == p_enable)", self.setter)
        self.assertIn("if (adjust_viewport_properties)", self.setter)

    def test_deferred_queue_coalesces(self):
        self.assertIn("if (property_adjust_queued)", self.queue)
        self.assertIn("call_deferred()", self.queue)

    def test_deferred_adjustment_honors_last_minute_opt_out(self):
        self.assertIn("if (!adjust_viewport_properties)", self.adjust)
        self.assertLess(self.adjust.index("if (!adjust_viewport_properties)"),
                        self.adjust.index("for (Node *child"))

    def test_subviewport_types_only(self):
        self.assertIn("Object::cast_to<SubViewport>(child)", self.adjust)

    def test_visible_sets_always_update(self):
        self.assertIn("SubViewport::UPDATE_ALWAYS", self.adjust)

    def test_hidden_disables_update(self):
        self.assertIn("SubViewport::UPDATE_DISABLED", self.adjust)

    def test_enabled_adjustment_disables_local_input(self):
        self.assertIn("sub->set_handle_input_locally(false)", self.adjust)

    def test_new_children_trigger_scan(self):
        self.assertIn("child_entered_tree", self.cpp)

    def test_script_property_bound(self):
        self.assertIn('ADD_PROPERTY(PropertyInfo(Variant::BOOL, "adjust_viewport_properties")', self.cpp)

    def test_property_editor_is_read_only_only_when_enabled(self):
        fn = _method(self.viewport, "void SubViewport::_validate_property(")
        self.assertIn("is_adjust_viewport_properties_enabled()", fn)
        self.assertIn("PROPERTY_USAGE_READ_ONLY", fn)

    def test_xml_docs_default_on(self):
        member = next((x for x in self.docs.findall("./members/member")
                       if x.get("name") == "adjust_viewport_properties"), None)
        self.assertIsNotNone(member)
        self.assertEqual(member.get("default"), "true")

    def test_native_cases_exist(self):
        src = (ROOT / "tests/scene/test_viewport.cpp").read_text()
        self.assertIn("Optional property adjustment", src)
        self.assertIn("Disable cancels queued adjustments", src)

    @unittest.skipUnless(shutil.which("c++"), "No C++ compiler")
    def test_compiled_real_accessors(self):
        fake = """
struct SubViewportContainer {
    bool adjust_viewport_properties = true;
    int queued = 0;
    void _queue_adjust_viewport_properties() { ++queued; }
    void set_adjust_viewport_properties(bool);
    bool is_adjust_viewport_properties_enabled() const;
};
"""
        checks = """
int main() {
    SubViewportContainer x;
    if (!x.is_adjust_viewport_properties_enabled()) return 1;
    x.set_adjust_viewport_properties(true);
    if (x.queued != 0) return 2;
    x.set_adjust_viewport_properties(false);
    if (x.queued != 0 || x.is_adjust_viewport_properties_enabled()) return 3;
    x.set_adjust_viewport_properties(true);
    if (x.queued != 1 || !x.is_adjust_viewport_properties_enabled()) return 4;
    return 0;
}
"""
        with tempfile.TemporaryDirectory() as tmp:
            exe = str(Path(tmp) / "test")
            result = subprocess.run(["c++", "-std=c++17", "-Wall", "-Wextra", "-Werror",
                                     "-x", "c++", "-", "-o", exe],
                                    input=fake + self.setter + self.getter + checks,
                                    text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            result = subprocess.run([exe], capture_output=True)
            self.assertEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
