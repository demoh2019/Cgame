#!/usr/bin/env python3
"""Upstream #115981 CanvasLayer/Window workspace routing source regressions.

These contracts inspect production C++ and require an editor GUI test for
end-to-end verification.
"""

from pathlib import Path
import unittest

SOURCE = Path(__file__).resolve().parents[3] / "editor/scene/canvas_item_editor_plugin.cpp"


def method(source: str, signature: str) -> str:
    pos = source.index(signature)
    brace = source.index("{", pos)
    depth = 0
    for cursor in range(brace, len(source)):
        if source[cursor] == "{":
            depth += 1
        elif source[cursor] == "}":
            depth -= 1
            if depth == 0:
                return source[brace + 1:cursor]
    raise AssertionError(f"Unclosed function: {signature}")


class CanvasWorkspaceRoutingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = SOURCE.read_text(encoding="utf-8")
        cls.handles = method(cls.source, "bool CanvasItemEditorPlugin::handles(Object *p_object) const")
        cls.edit = method(cls.source, "void CanvasItemEditorPlugin::edit(Object *p_object)")
        cls.visible = method(cls.source, "void CanvasItemEditorPlugin::make_visible(bool p_visible)")
        cls.select = method(cls.source, "bool CanvasItemEditor::_select_click_on_item(")

    def test_canvas_item_remains_supported(self):
        self.assertIn("Object::cast_to<CanvasItem>(p_object) != nullptr", self.handles)

    def test_canvas_layer_switches_to_2d_editor(self):
        self.assertIn("Object::cast_to<CanvasLayer>(p_object) != nullptr", self.handles)

    def test_window_switches_to_2d_editor(self):
        self.assertIn("Object::cast_to<Window>(p_object) != nullptr", self.handles)

    def test_all_three_types_checked(self):
        self.assertEqual(self.handles.count("Object::cast_to<"), 3)

    def test_supported_types_are_combined_with_or(self):
        self.assertEqual(self.handles.count("||"), 2)
        self.assertNotIn("&&", self.handles)

    def test_null_checks_are_explicit(self):
        self.assertEqual(self.handles.count("!= nullptr"), 3)

    def test_handles_has_only_one_return(self):
        self.assertEqual(self.handles.count("return "), 1)

    def test_no_string_based_type_matching(self):
        self.assertNotIn("get_class()", self.handles)
        self.assertNotIn("is_class(", self.handles)

    def test_edit_maintains_canvas_item_cast(self):
        self.assertIn("canvas_item_editor->edit(Object::cast_to<CanvasItem>(p_object))", self.edit)

    def test_make_visible_opens_canvas_editor(self):
        self.assertIn("if (p_visible)", self.visible)
        self.assertIn("canvas_item_editor->make_visible()", self.visible)

    def test_shift_selection_uses_full_selection_list(self):
        self.assertIn("get_full_selected_node_list()", self.select)

    def test_shift_selection_no_stale_top_node_list(self):
        self.assertNotIn("get_top_selected_node_list()", self.select)

    def test_shift_toggle_removes_selected_node(self):
        self.assertIn("if (editor_selection->is_selected(node))", self.select)
        self.assertIn("editor_selection->remove_node(node)", self.select)

    def test_shift_append_keeps_existing_selection(self):
        self.assertIn("if (p_append && !full_node_list.is_empty())", self.select)
        self.assertIn("editor_selection->add_node(node)", self.select)

    def test_single_selection_clears_before_add(self):
        self.assertIn("editor_selection->clear();", self.select)
        self.assertIn("editor_selection->add_node(node);", self.select)

    def test_selection_changes_request_redraw(self):
        self.assertIn("viewport->queue_redraw()", self.select)


if __name__ == "__main__":
    unittest.main()
