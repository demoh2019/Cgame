"""Source contracts for low-allocation Node.find_children iterative traversal."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
SOURCE = (ROOT / "scene/main/node.cpp").read_text(encoding="utf-8")
TEST = (ROOT / "tests/scene/test_node.cpp").read_text(encoding="utf-8")
BENCH = (ROOT / "misc/scripts/benchmarks/benchmark_node_find_children.gd").read_text(encoding="utf-8")
START = SOURCE.index("TypedArray<Node> Node::find_children(")
END = SOURCE.index("void Node::reparent(", START)
BODY = SOURCE[START:END]


class NodeFindChildrenPerfContracts(unittest.TestCase):
    def test_one_typed_array_accumulates_all_results(self):
        self.assertEqual(BODY.count("TypedArray<Node> ret;"), 1)
        self.assertNotIn("ret.append_array(", BODY)

    def test_no_recursive_find_children_calls(self):
        self.assertEqual(BODY.count("find_children("), 1)

    def test_stack_allocations_scale_with_depth(self):
        self.assertIn("struct TraversalFrame", BODY)
        self.assertIn("LocalVector<TraversalFrame> frames", BODY)
        self.assertIn("frames.push_back({ child, 0 });", BODY)

    def test_direct_children_use_no_stack(self):
        self.assertLess(BODY.index("if (!p_recursive)"), BODY.index("struct TraversalFrame"))
        self.assertIn("return ret;", BODY[BODY.index("if (!p_recursive)"):BODY.index("struct TraversalFrame")])

    def test_unowned_branches_are_pruned(self):
        self.assertIn("if (p_owned && !child->data.owner)", BODY)
        self.assertIn("continue;", BODY[BODY.index("if (p_owned && !child->data.owner)"):])

    def test_type_registry_lookup_is_not_repeated_per_node(self):
        self.assertEqual(BODY.count("ScriptServer::is_global_class(p_type)"), 1)
        self.assertEqual(BODY.count("ScriptServer::get_global_class_path(p_type)"), 1)

    def test_preserves_type_and_name_checks(self):
        self.assertIn("p_node->data.name.string().match(p_pattern)", BODY)
        self.assertIn("p_node->is_class(p_type)", BODY)
        self.assertIn("script_ref->get_base_script()", BODY)

    def test_native_regressions_cover_order_ownership_and_depth(self):
        self.assertIn("find_children iterative traversal preserves node ordering and ownership", TEST)
        self.assertIn("Node::INTERNAL_MODE_FRONT", TEST)
        self.assertIn("Node::INTERNAL_MODE_BACK", TEST)
        self.assertIn("find_children iterative traversal handles deep scene trees", TEST)

    def test_benchmark_reports_microseconds_per_query(self):
        self.assertIn("Time.get_ticks_usec()", BENCH)
        self.assertIn("usec/query", BENCH)


if __name__ == "__main__":
    unittest.main()
