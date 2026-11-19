#!/usr/bin/env python3
"""Source regression contracts for Node::find_children single-result traversal.

Native integration behavior is checked separately by the editor's doctest
suite. These checks guard against reintroducing per-descendant arrays.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
CPP = ROOT / "scene/main/node.cpp"
HEADER = ROOT / "scene/main/node.h"
TEST = ROOT / "tests/scene/test_node_find_children_fast.cpp"


class FindChildrenContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cpp = CPP.read_text(encoding="utf-8")
        cls.header = HEADER.read_text(encoding="utf-8")
        cls.native = TEST.read_text(encoding="utf-8")
        cls.start = cls.cpp.index("void Node::_append_find_children(")
        cls.end = cls.cpp.index("\nvoid Node::reparent(", cls.start)
        cls.section = cls.cpp[cls.start:cls.end]

    def test_helper_signature_and_single_result(self):
        self.assertIn(
            "void _append_find_children(const String &p_pattern, const String &p_type,"
            " bool p_recursive, bool p_owned, TypedArray<Node> &r_result) const;",
            self.header,
        )
        self.assertIn("TypedArray<Node> &r_result", self.section)
        self.assertIn("r_result.append(cptr[i]);", self.section)
        self.assertNotIn("ret.append_array(", self.section)

    def test_public_api_retained(self):
        self.assertRegex(self.section, r"TypedArray<Node> Node::find_children\([^)]*\) const")
        self.assertIn("ERR_THREAD_GUARD_V(TypedArray<Node>());", self.section)
        self.assertIn("ERR_FAIL_COND_V(p_pattern.is_empty() && p_type.is_empty(), ret);", self.section)
        self.assertIn("_append_find_children(p_pattern, p_type, p_recursive, p_owned, ret);", self.section)

    def test_recursion_does_not_allocate_arrays(self):
        self.assertIn(
            "cptr[i]->_append_find_children(p_pattern, p_type, true, p_owned, r_result);",
            self.section,
        )
        self.assertNotIn("cptr[i]->find_children(", self.section)
        helper_section = self.section[:self.section.index("TypedArray<Node> Node::find_children(")]
        self.assertNotIn("TypedArray<Node> ret;", helper_section)

    def test_thread_guard_retained_at_each_level(self):
        helper = self.section[:self.section.index("TypedArray<Node> Node::find_children(")]
        self.assertIn("ERR_THREAD_GUARD;", helper)

    def test_filters_and_script_inheritance_retained(self):
        for required in (
            "p_owned && !cptr[i]->data.owner",
            "p_pattern.is_empty() || cptr[i]->data.name.string().match(p_pattern)",
            "p_type.is_empty() || cptr[i]->is_class(p_type)",
            "ScriptServer::is_global_class(p_type)",
            "scr = scr->get_base_script();",
        ):
            with self.subTest(fragment=required):
                self.assertIn(required, self.section)

    def test_snapshot_child_iteration_unmodified(self):
        self.assertIn("_update_children_cache();", self.section)
        self.assertIn("Node *const *cptr = data.children_cache.ptr();", self.section)
        self.assertIn("const int ccount = data.children_cache.size();", self.section)
        self.assertIn("for (int i = 0; i < ccount; i++)", self.section)

    def test_native_regression_cases_exist(self):
        self.assertIn("TEST_FORCE_LINK(test_node_find_children_fast)", self.native)
        self.assertEqual(len(re.findall(r"TEST_CASE\(", self.native)), 6)
        for fragment in (
            "Recursive results retain depth-first tree ordering",
            "Nonrecursive lookup excludes grandchildren",
            "Name and built-in type filters work together",
            "Owned-only lookup excludes unowned subtrees",
            "Empty input rejected and missing matches empty",
            "Repeated queries and mutations are independent",
        ):
            self.assertIn(fragment, self.native)


if __name__ == "__main__":
    unittest.main()
