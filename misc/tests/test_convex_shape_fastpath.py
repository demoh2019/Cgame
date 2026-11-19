"""Convex collision vertex preallocation source contracts."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
TEXT = (ROOT / "scene/resources/mesh.cpp").read_text(encoding="utf-8")
BODY = TEXT.split("Ref<ConvexPolygonShape3D> Mesh::create_convex_shape(", 1)[1].split(
    "Ref<ConcavePolygonShape3D> Mesh::create_trimesh_shape()", 1)[0]


class ConvexShapeFastPath(unittest.TestCase):
    def test_exact_reserve_from_surface_metadata(self):
        self.assertIn("total_vertices += MAX(0, surface_get_array_len(i));", BODY)
        self.assertIn("vertices.reserve_exact((int)total_vertices)", BODY)

    def test_reserve_happens_before_surface_concatenation(self):
        self.assertLess(BODY.index("vertices.reserve_exact("), BODY.index("vertices.append_array(v);"))
        self.assertIn("const int surface_count = get_surface_count();", BODY)

    def test_large_vertex_count_cannot_overflow_reservation(self):
        self.assertIn("int64_t total_vertices = 0;", BODY)
        self.assertIn("ERR_FAIL_COND_V(total_vertices > INT32_MAX", BODY)
        self.assertIn("if (total_vertices > 0)", BODY)

    def test_existing_convex_clean_and_simplify_paths_still_work(self):
        self.assertLess(BODY.index("if (p_simplify)"), BODY.index("int64_t total_vertices"))
        self.assertIn("ConvexHullComputer::convex_hull(vertices, md)", BODY)
        self.assertIn("shape->set_points(vertices);", BODY)

    def test_surface_arrays_remain_read_only(self):
        self.assertIn("Array a = surface_get_arrays(i);", BODY)
        self.assertIn("Vector<Vector3> v = a[ARRAY_VERTEX];", BODY)
        self.assertNotIn("v.ptrw()", BODY)


if __name__ == "__main__":
    unittest.main()
