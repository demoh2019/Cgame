"""Contracts for convex BVH traversal pruning; native C++ tests verify results.

Run:
    python3 -m unittest tests.stress.test_bvh_convex_pruning -v
"""

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
CULL = ROOT / "core/math/bvh_cull.inc"
NATIVE_TESTS = ROOT / "tests/core/math/test_bvh.cpp"


class ConvexBVHTraversalContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cpp = CULL.read_text(encoding="utf-8")
        cls.code = cpp.split("bool _cull_convex_iterative(", 1)[1]
        cls.tests = NATIVE_TESTS.read_text(encoding="utf-8")

    def test_missed_root_is_rejected_before_stack_and_plane_allocations(self):
        code = self.code
        self.assertIn("root_result = _nodes[p_node_id].aabb.intersects_convex(r_params.hull)", code)
        self.assertIn("if (root_result == BVHABB_CLASS::IR_MISS)", code)
        self.assertLess(code.index("root_result ="), code.index("alloca(ii.get_alloca_stacksize())"))
        self.assertLess(code.index("root_result ="), code.index("alloca(sizeof(uint32_t) * max_planes)"))

    def test_children_are_classified_once_before_entering_stack(self):
        code = self.code
        self.assertIn("child_result = _nodes[child_id].aabb.intersects_convex(r_params.hull)", code)
        self.assertIn("if (child_result == BVHABB_CLASS::IR_MISS)", code)
        self.assertIn("child_fully_within = child_result == BVHABB_CLASS::IR_FULL", code)
        self.assertLess(code.index("child_result ="), code.index("CullConvexParams *child = ii.request()"))
        self.assertIn("child->fully_within = child_fully_within;", code)
        self.assertNotIn("tnode.aabb.intersects_convex(r_params.hull)", code)

    def test_result_capacity_masks_slanted_planes_and_updates_are_covered(self):
        self.assertIn(
            'TEST_CASE("[BVH] 3D convex traversal prunes sparse subtrees without losing hits")',
            self.tests,
        )
        self.assertIn("hull_between_x(1000, 1100)", self.tests)
        self.assertIn("hull_between_x(-600, 600)", self.tests)
        self.assertIn("slanted_hull.push_back(Plane(", self.tests)
        self.assertIn("results, COUNT, nullptr, 1)", self.tests)
        self.assertIn("results, COUNT, nullptr, 2)", self.tests)
        self.assertIn("results, 1, nullptr)", self.tests)
        self.assertIn("tree.move(handles[0]", self.tests)
        self.assertIn("tree.erase(handles[48])", self.tests)


if __name__ == "__main__":
    unittest.main()
