#!/usr/bin/env python3
"""Source contracts for the allocation-free Node.find_children traversal.

Runtime correctness is exercised by the native test_node_find_children_fast.cpp
suite. These checks ensure the iterative DFS avoids per-descendant Array
allocations and preserves key filtering rules.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
CPP = ROOT / "scene/main/node.cpp"
NATIVE = ROOT / "tests/scene/test_node_find_children_fast.cpp"


class FindChildrenFastContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source = CPP.read_text(encoding="utf-8")
        start = source.index("TypedArray<Node> Node::find_children(")
        end = source.index("\nvoid Node::reparent(", start)
        cls.section = source[start:end]
        cls.native = NATIVE.read_text(encoding="utf-8")

    def test_public_signature_and_thread_guard(self):
        self.assertRegex(self.section, r"TypedArray<Node> Node::find_children\([^)]*\) const")
        self.assertIn("ERR_THREAD_GUARD_V(TypedArray<Node>());", self.section)

    def test_no_recursive_typed_array_construction(self):
        self.assertEqual(self.section.count("TypedArray<Node> ret;"), 1)
        self.assertNotIn("ret.append_array(", self.section)
        self.assertNotIn("child->find_children(", self.section)

    def test_depth_first_stack_uses_only_current_path(self):
        self.assertIn("struct TraversalFrame", self.section)
        self.assertIn("LocalVector<TraversalFrame> frames;", self.section)
        self.assertIn("frames.push_back({ this, 0 });", self.section)
        self.assertIn("frames.resize(frames.size() - 1);", self.section)
        self.assertIn("frame.parent->data.children_cache", self.section)

    def test_nonrecursive_fast_path_retained(self):
        self.assertIn("if (!p_recursive)", self.section)
        self.assertIn("for (Node *child : data.children_cache)", self.section)
        self.assertIn("return ret;", self.section)

    def test_owned_only_skips_unowned_subtree(self):
        self.assertIn("if (p_owned && !child->data.owner)", self.section)
        self.assertIn("continue;", self.section)

    def test_filters_and_script_path_matching(self):
        for statement in (
            "ScriptServer::is_global_class(p_type)",
            "ScriptServer::get_global_class_path(p_type)",
            "p_node->data.name.string().match(p_pattern)",
            "p_node->is_class(p_type)",
            "script_ref = script_ref->get_base_script();",
            "ret.append(p_node);",
        ):
            with self.subTest(statement=statement):
                self.assertIn(statement, self.section)

    def test_six_native_behavior_regressions(self):
        self.assertIn("TEST_FORCE_LINK(test_node_find_children_fast)", self.native)
        self.assertEqual(len(re.findall(r"TEST_CASE\(", self.native)), 6)
        for case in (
            "Recursive results retain depth-first tree ordering",
            "Nonrecursive lookup excludes grandchildren",
            "Name and built-in type filters work together",
            "Owned-only lookup excludes unowned subtrees",
            "Empty input rejected and missing matches empty",
            "Repeated queries and mutations are independent",
        ):
            self.assertIn(case, self.native)


if __name__ == "__main__":
    unittest.main()
