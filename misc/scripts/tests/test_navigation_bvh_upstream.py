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


if __name__ == "__main__":
    unittest.main()
