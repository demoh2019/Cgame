"""Verify Node::find_children traversal uses O(1) temporary storage."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]


class NodeFindChildrenContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source = (ROOT / "scene/main/node.cpp").read_text()
        cls.method = source.split("TypedArray<Node> Node::find_children(", 1)[1].split(
            "\nvoid Node::reparent(", 1)[0]

    def test_recursive_path_is_allocation_free(self):
        self.assertNotIn("LocalVector<TraversalFrame>", self.method)
        self.assertNotIn("frames.push_back", self.method)
        self.assertNotIn("find_children(p_pattern", self.method)
        self.assertIn("while (current_node != this)", self.method)

    def test_internal_child_index_offsets_are_preserved(self):
        self.assertIn("INTERNAL_MODE_FRONT", self.method)
        self.assertIn("INTERNAL_MODE_BACK", self.method)
        self.assertIn("parent->data.internal_children_front_count_cache", self.method)
        self.assertIn("parent->data.external_children_count_cache", self.method)
        self.assertIn("current_node->data.index + 1", self.method)

    def test_owned_subtree_and_nonrecursive_semantics_preserved(self):
        self.assertIn("if (!p_owned || current_node->data.owner)", self.method)
        self.assertIn("if (!p_recursive)", self.method)
        self.assertIn("append_match(current_node)", self.method)
        self.assertIn("current_node->_update_children_cache()", self.method)

if __name__ == "__main__":
    unittest.main()
