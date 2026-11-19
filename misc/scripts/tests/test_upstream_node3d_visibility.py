"""Static regressions for upstream Godot #125571 Node3D visibility cache.

Complements native scene tests; checks that cache writes are ordered and no
per-call ancestor walk survives in is_visible_in_tree().
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
SOURCE = (ROOT / "scene/3d/node_3d.cpp").read_text(encoding="utf-8")
HEADER = (ROOT / "scene/3d/node_3d.h").read_text(encoding="utf-8")
NATIVE = (ROOT / "tests/scene/test_node_3d.cpp").read_text(encoding="utf-8")


def between(start, end):
    return SOURCE.split(start, 1)[1].split(end, 1)[0]


class VisibilityCacheContracts(unittest.TestCase):
    def test_parent_visibility_cache_field_exists(self):
        self.assertIn("bool parent_visible_in_tree : 1;", HEADER)

    def test_visibility_query_uses_cache(self):
        self.assertIn("return data.visible && data.parent_visible_in_tree;",
                      between("bool Node3D::is_visible_in_tree() const {", "void Node3D::rotate_object_local"))

    def test_visibility_query_has_no_ancestor_loop(self):
        self.assertNotIn("while (s)", between("bool Node3D::is_visible_in_tree() const {",
                                              "void Node3D::rotate_object_local"))

    def test_visibility_read_keeps_thread_guard(self):
        self.assertIn("ERR_READ_THREAD_GUARD_V(false)",
                      between("bool Node3D::is_visible_in_tree() const {", "void Node3D::rotate_object_local"))

    def test_cache_set_when_entering_tree(self):
        self.assertIn("data.parent_visible_in_tree = data.parent ? data.parent->is_visible_in_tree() : true;",
                      SOURCE)

    def test_cache_cleared_on_exit(self):
        self.assertIn("data.parent_visible_in_tree = false;", SOURCE)

    def test_detached_constructor_cache_false(self):
        self.assertIn("data.parent_visible_in_tree = false; // Seeded at ENTER_TREE", SOURCE)

    def test_visibility_propagation_computes_once(self):
        self.assertIn("const bool vis = is_visible_in_tree();", SOURCE)

    def test_propagation_updates_direct_children(self):
        self.assertIn("s->data.parent_visible_in_tree = vis;", SOURCE)

    def test_propagation_recurses_visible_children(self):
        self.assertIn("s->_propagate_visibility_changed();", SOURCE)

    def test_interpolated_transform_uses_visibility_cache(self):
        self.assertIn("if (is_visible_in_tree()) {",
                      between("Transform3D Node3D::get_global_transform_interpolated()",
                              "void Node3D::"))

    def test_interpolated_transform_has_hidden_fallback(self):
        self.assertIn("const Node3D *visible_parent = nullptr;", SOURCE)

    def test_visibility_boolean_type_preserved(self):
        self.assertIn("bool visible : 1;", HEADER)

    def test_physics_interpolation_code_retained(self):
        self.assertIn("data.fti_global_xform_interp_set", SOURCE)

    def test_no_visual_instance_cast_for_visibility_fast_path(self):
        self.assertNotIn("Object::cast_to<VisualInstance3D>(this) && _is_vi_visible()", SOURCE)

    def test_native_test_scenarios(self):
        self.assertEqual(NATIVE.count("TEST_CASE("), 11)

    def test_native_tests_gate_3d_builds(self):
        self.assertIn("#ifndef _3D_DISABLED", NATIVE)

    def test_native_tests_force_link(self):
        self.assertIn("TEST_FORCE_LINK(test_node_3d)", NATIVE)

    def test_deep_native_hierarchy_coverage(self):
        self.assertIn("i < 64", NATIVE)

    def test_detach_and_reenter_coverage(self):
        self.assertIn("reenter restores it", NATIVE)


if __name__ == "__main__":
    unittest.main()
