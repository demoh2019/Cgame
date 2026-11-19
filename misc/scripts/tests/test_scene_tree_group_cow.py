#!/usr/bin/env python3
"""Regression contracts for zero-copy SceneTree group snapshot reads.

Structural checks complement (and do not replace) native mutation, ordering,
and vector COW tests in tests/scene/test_scene_tree_group_snapshots.cpp.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
SCENE_TREE = ROOT / "scene/main/scene_tree.cpp"
NATIVE_TEST = ROOT / "tests/scene/test_scene_tree_group_snapshots.cpp"

def function_body(source: str, signature: str, next_signature: str) -> str:
    start = source.index(signature)
    end = source.index(next_signature, start + len(signature))
    return source[start:end]

class TestSceneTreeZeroCopy(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = SCENE_TREE.read_text(encoding="utf-8")

    def test_call_group_uses_const_snapshot(self):
        body = function_body(
            self.source, "void SceneTree::call_group_flagsp(",
            "void SceneTree::notify_group_flags("
        )
        self.assertIn("nodes_copy = g.nodes;", body)
        self.assertIn("Node *const *gr_nodes = nodes_copy.ptr();", body)
        self.assertNotIn("nodes_copy.ptrw()", body)

    def test_notify_group_uses_const_snapshot(self):
        body = function_body(
            self.source, "void SceneTree::notify_group_flags(",
            "void SceneTree::set_group_flags("
        )
        self.assertIn("nodes_copy = g.nodes;", body)
        self.assertIn("Node *const *gr_nodes = nodes_copy.ptr();", body)
        self.assertNotIn("nodes_copy.ptrw()", body)

    def test_set_group_uses_const_snapshot(self):
        body = function_body(
            self.source, "void SceneTree::set_group_flags(",
            "void SceneTree::notify_group("
        )
        self.assertIn("nodes_copy = g.nodes;", body)
        self.assertIn("Node *const *gr_nodes = nodes_copy.ptr();", body)
        self.assertNotIn("nodes_copy.ptrw()", body)

    def test_input_dispatch_uses_const_snapshot(self):
        body = function_body(
            self.source, "void SceneTree::_call_input_pause(",
            "void SceneTree::_call_input_text("
        ) if "void SceneTree::_call_input_text(" in self.source else function_body(
            self.source, "void SceneTree::_call_input_pause(",
            "TypedArray<Node> SceneTree::_get_nodes_in_group("
        )
        self.assertIn("nodes_copy = g.nodes;", body)
        self.assertIn("Node *const *gr_nodes = nodes_copy.ptr();", body)
        self.assertNotIn("nodes_copy.ptrw()", body)

    def test_group_query_uses_const_read(self):
        body = function_body(
            self.source, "TypedArray<Node> SceneTree::_get_nodes_in_group(",
            "bool SceneTree::has_group("
        )
        self.assertIn("Node *const *ptr = E->value.nodes.ptr();", body)
        self.assertNotIn("E->value.nodes.ptrw()", body)

    def test_all_five_paths_covered(self):
        self.assertEqual(
            len(re.findall(r"Node \*const \*gr_nodes = nodes_copy\.ptr\(\);", self.source)),
            4
        )
        self.assertNotIn("nodes_copy.ptrw()", self.source)

    def test_native_tests_exercise_real_group_callbacks(self):
        native = NATIVE_TEST.read_text(encoding="utf-8")
        for fragment in (
            'TEST_FORCE_LINK(test_scene_tree_group_snapshots)',
            'CHECK(snapshot.ptr() == nodes.ptr());',
            'remove_target->remove_from_group(group_name);',
            'add_target->add_to_group(group_name);',
            'tree->notify_group_flags(SceneTree::GROUP_CALL_REVERSE',
            'tree->call_group(group, "set_process_priority"',
            'tree->set_group(group, "process_priority"',
        ):
            with self.subTest(fragment=fragment):
                self.assertIn(fragment, native)

if __name__ == "__main__":
    unittest.main()
