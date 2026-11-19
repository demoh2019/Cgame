"""Regression contracts for allocation-free, literal Node name lookup hot paths.

These check that exact matching uses an interned name and existing per-parent
hash table, while wildcard and recursion semantics remain intact.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
SOURCE = (ROOT / "scene/main/node.cpp").read_text(encoding="utf-8")
NATIVE = (ROOT / "tests/scene/test_node_find_children_fast.cpp").read_text(encoding="utf-8")

def block(start, end):
    return SOURCE.split(start, 1)[1].split(end, 1)[0]

class ExactNodeLookupContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.child = block("Node *Node::find_child(", "// Finds child nodes based on their name")
        cls.children = block("TypedArray<Node> Node::find_children(", "void Node::reparent(")
        cls.parent = block("Node *Node::find_parent(", "void Node::set_unique_scene_id(")

    def test_child_rejects_empty_pattern(self):
        self.assertIn("ERR_FAIL_COND_V(p_pattern.is_empty(), nullptr);", self.child)

    def test_child_detects_both_wildcards(self):
        self.assertIn("!p_pattern.contains_char('*') && !p_pattern.contains_char('?')", self.child)

    def test_child_interns_exact_string_once(self):
        self.assertIn("const StringName exact_name(p_pattern);", self.child)

    def test_child_nonrecursive_direct_name_hash(self):
        self.assertIn("_get_child_by_name(exact_name)", self.child)

    def test_child_direct_lookup_before_cache_materialization(self):
        self.assertLess(self.child.index("_get_child_by_name(exact_name)"), self.child.index("_update_children_cache();"))

    def test_child_preserves_owner_filter(self):
        self.assertIn("child && (!p_owned || child->data.owner)", self.child)
        self.assertIn("if (p_owned && !child->data.owner)", self.child)

    def test_child_recursive_depth_first(self):
        self.assertIn("if (Node *match = self(self, child))", self.child)
        self.assertIn("return match;", self.child)

    def test_child_recursive_propagates_cache_updates(self):
        self.assertIn("p_parent->_update_children_cache();", self.child)

    def test_child_exact_compares_interned_names(self):
        self.assertIn("child->data.name == exact_name", self.child)

    def test_child_wildcard_fallback_remains(self):
        self.assertIn("cptr[i]->data.name.string().match(p_pattern)", self.child)
        self.assertIn("cptr[i]->find_child(p_pattern, true, p_owned)", self.child)

    def test_children_exact_only_for_nonempty_names(self):
        self.assertIn("!p_pattern.is_empty() && !p_pattern.contains_char('*')", self.children)

    def test_children_exact_type_filter_preserved(self):
        self.assertIn("p_type.is_empty() || p_node->is_class(p_type)", self.children)
        self.assertIn("append_match(child);", self.children)

    def test_children_nonrecursive_uses_hash(self):
        self.assertIn("Node *child = _get_child_by_name(exact_name);", self.children)

    def test_children_wildcards_preserved(self):
        self.assertIn("p_node->data.name.string().match(p_pattern)", self.children)

    def test_children_recursive_traversal_kept(self):
        self.assertIn("while (current_node != this)", self.children)

    def test_parent_exact_name_and_wildcards(self):
        self.assertIn("p->data.name == exact_name", self.parent)
        self.assertIn("p->data.name.string().match(p_pattern)", self.parent)

    def test_parent_empty_pattern_rejected(self):
        self.assertIn("if (p_pattern.is_empty())", self.parent)

    def test_existing_native_cases_retained(self):
        self.assertIn("Recursive results retain depth-first tree ordering", NATIVE)
        self.assertIn("Owned-only lookup excludes unowned subtrees", NATIVE)

    def test_six_native_exact_lookup_cases(self):
        cases = [
            "Literal direct child lookup preserves name and ownership semantics",
            "Literal recursive lookup keeps depth-first precedence",
            "Literal find_children honors type and direct-child filtering",
            "Literal ownership excludes entire unowned branches",
            "Wildcard and question mark patterns remain supported",
            "Parent literal and wildcard paths agree",
        ]
        for case in cases:
            with self.subTest(case=case):
                self.assertIn('TEST_CASE("[NodeFindChildrenFast] ' + case + '")', NATIVE)

if __name__ == "__main__":
    unittest.main()
