"""Static integration contracts for upstream Godot #125543 navigation BVH.

The native test test_navigation_polygon_bvh.cpp separately checks exact nearest
polygon correctness for empty, linear-scan, and BVH regions.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]


def load(path):
    return (ROOT / path).read_text(encoding="utf-8")


class NavigationBVHContracts(unittest.TestCase):
    def test_both_navigation_dimensions_have_bvh(self):
        for dim in ("2d", "3d"):
            with self.subTest(dim=dim):
                self.assertIn(f"class NavPolygonBVH{dim.upper()}", load(f"modules/navigation_{dim}/{dim}/nav_polygon_bvh_{dim}.h"))

    def test_small_regions_preserve_linear_scan(self):
        for dim in ("2d", "3d"):
            with self.subTest(dim=dim):
                self.assertIn("if (count <= LEAF_SIZE)", load(f"modules/navigation_{dim}/{dim}/nav_polygon_bvh_{dim}.h"))
                self.assertIn("if (nodes.is_empty())", load(f"modules/navigation_{dim}/{dim}/nav_polygon_bvh_{dim}.h"))

    def test_build_occurs_after_region_edge_processing(self):
        for dim in ("2d", "3d"):
            with self.subTest(dim=dim):
                src = load(f"modules/navigation_{dim}/{dim}/nav_region_builder_{dim}.cpp")
                self.assertLess(src.index("_build_step_merge_edge_connection_pairs(r_build);"),
                                src.index("_build_step_build_polygon_bvh(r_build);"))
                self.assertLess(src.index("_build_step_build_polygon_bvh(r_build);"),
                                src.index("_build_update_iteration(r_build);"))

    def test_endpoint_queries_use_bvh_but_retain_original_scan(self):
        for dim in ("2d", "3d"):
            with self.subTest(dim=dim):
                src = load(f"modules/navigation_{dim}/{dim}/nav_mesh_queries_{dim}.cpp")
                self.assertEqual(src.count("polygon_bvh.find_closest_point("), 2)
                self.assertIn("if (!region->polygon_bvh.is_empty())", src)
                self.assertIn("for (const Polygon &p : region->get_navmesh_polygons())", src)

    def test_navigation_layers_checked_before_search(self):
        for dim in ("2d", "3d"):
            with self.subTest(dim=dim):
                src = load(f"modules/navigation_{dim}/{dim}/nav_mesh_queries_{dim}.cpp")
                self.assertIn("p_query_task.navigation_layers & region->get_navigation_layers()", src)

    def test_nearest_ties_retain_original_polygon_order(self):
        for dim in ("2d", "3d"):
            with self.subTest(dim=dim):
                src = load(f"modules/navigation_{dim}/{dim}/nav_polygon_bvh_{dim}.h")
                self.assertIn("p_polygon_id < r_polygon_id", src)

    def test_bvh_has_bounded_stack_and_memory_accounting(self):
        for dim in ("2d", "3d"):
            with self.subTest(dim=dim):
                src = load(f"modules/navigation_{dim}/{dim}/nav_polygon_bvh_{dim}.h")
                self.assertIn("STACK_SIZE = 64", src)
                self.assertIn("get_size_bytes() const", src)
                self.assertIn("get_capacity()", src)

    def test_native_correctness_compares_bruteforce(self):
        src = load("tests/servers/test_navigation_polygon_bvh.cpp")
        for text in ("0, 1, 8, 9, 400", "for (int probe = 0; probe < 80; probe++)",
                     "CHECK(found_polygon == expected_polygon);",
                     "CHECK(found_point.is_equal_approx(expected_point));"):
            with self.subTest(text=text):
                self.assertIn(text, src)



    def test_hotpath_avoids_sqrt_for_aabb_nodes(self):
        for dim in ("2d", "3d"):
            with self.subTest(dimension=dim):
                src = load(f"modules/navigation_{dim}/{dim}/nav_polygon_bvh_{dim}.h")
                self.assertNotIn("Math::sqrt(_distance_squared(", src)
                self.assertIn("prune_distance_sq = prune_distance * prune_distance;", src)
                self.assertIn("_distance_squared(p_point, node.bounds) > prune_distance_sq", src)

    def test_hotpath_sorts_child_bounds_without_sqrt(self):
        for dim in ("2d", "3d"):
            with self.subTest(dimension=dim):
                src = load(f"modules/navigation_{dim}/{dim}/nav_polygon_bvh_{dim}.h")
                self.assertIn("left_distance_sq = _distance_squared(", src)
                self.assertIn("right_distance_sq = _distance_squared(", src)
                self.assertIn("left_distance_sq < right_distance_sq", src)

    def test_hotpath_preserves_rounding_slack_for_tied_polygons(self):
        for dim in ("2d", "3d"):
            with self.subTest(dimension=dim):
                src = load(f"modules/navigation_{dim}/{dim}/nav_polygon_bvh_{dim}.h")
                self.assertIn("r_distance + CMP_EPSILON", src)
                self.assertGreaterEqual(src.count("<= prune_distance_sq"), 4)

    def test_extended_native_query_and_memory_regressions(self):
        src = load("tests/servers/test_nav_polygon_bvh.cpp")
        self.assertEqual(src.count("TEST_CASE("), 16)
        for marker in ("Large grid matches original polygon scan",
                       "Equal-distance ties retain original polygon order",
                       "Rebuilding smaller input releases BVH memory",
                       "Existing better match is not overwritten"):
            self.assertEqual(src.count(marker), 2)

    def test_native_benchmarks_report_both_dimensions_and_memory(self):
        src = load("tests/servers/test_nav_polygon_bvh.cpp")
        self.assertIn("Navigation 2D BVH endpoint benchmark", src)
        self.assertIn("Navigation 3D BVH endpoint benchmark", src)
        self.assertEqual(src.count("x 512 queries:"), 2)
        self.assertEqual(src.count("get_size_bytes()"), 12)


    def test_bvh_allocates_exact_number_of_nodes_once(self):
        for dim in ("2d", "3d"):
            with self.subTest(dim=dim):
                src = load(f"modules/navigation_{dim}/{dim}/nav_polygon_bvh_{dim}.h")
                self.assertIn("nodes.reserve(_count_nodes(polygon_indices.size()));", src)

    def test_preallocation_counts_same_median_split_as_builder(self):
        for dim in ("2d", "3d"):
            with self.subTest(dim=dim):
                src = load(f"modules/navigation_{dim}/{dim}/nav_polygon_bvh_{dim}.h")
                self.assertIn("static uint32_t _count_nodes(uint32_t p_count)", src)
                self.assertIn("if (p_count <= LEAF_SIZE)", src)
                self.assertIn("_count_nodes(left_count) + _count_nodes(p_count - left_count)", src)

    def test_bvh_preallocation_preserves_short_region_fast_path(self):
        for dim in ("2d", "3d"):
            with self.subTest(dim=dim):
                src = load(f"modules/navigation_{dim}/{dim}/nav_polygon_bvh_{dim}.h")
                self.assertLess(src.index("if (count <= LEAF_SIZE)"),
                                src.index("nodes.reserve(_count_nodes("))

if __name__ == "__main__":
    unittest.main()
