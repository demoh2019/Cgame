"""Native navigation debug mesh memory contract checks."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SOURCE = (ROOT / "scene/resources/navigation_mesh.cpp").read_text(encoding="utf-8")
BODY = SOURCE.split("Ref<ArrayMesh> NavigationMesh::get_debug_mesh() {", 1)[1].split(
    "\n#endif // DEBUG_ENABLED", 1)[0]


class NavigationDebugMeshFastPath(unittest.TestCase):
    def test_face_buffer_has_exact_triangle_capacity_without_append(self):
        self.assertIn("face_vertex_array.resize(polygon_count * 3);", BODY)
        self.assertIn("Vector3 *face_write = face_vertex_array.ptrw();", BODY)
        self.assertNotIn("face_vertex_array.push_back(", BODY)
        self.assertIn("face_write[base + 2] = vertex_data[polygon[2]];", BODY)

    def test_color_buffer_has_exact_triangle_capacity_without_append(self):
        self.assertIn("face_color_array.resize(polygon_count * 3);", BODY)
        self.assertIn("Color *color_write = face_color_array.ptrw();", BODY)
        self.assertNotIn("face_color_array.push_back(", BODY)
        for i in range(3):
            self.assertIn(f"color_write[base + {i}] = polygon_color;", BODY)

    def test_edges_write_exactly_six_endpoints_per_polygon(self):
        self.assertIn("line_vertex_array.resize(polygon_count * 6);", BODY)
        self.assertIn("Vector3 *line_write = line_vertex_array.ptrw();", BODY)
        self.assertNotIn("line_vertex_array.push_back(", BODY)
        for i, name in enumerate(("v0", "v1", "v1", "v2", "v2", "v0")):
            self.assertIn(f"line_write[base + {i}] = {name};", BODY)

    def test_polygons_are_not_copied_individually(self):
        self.assertIn("const Vector<int> &polygon = polygons[i];", BODY)
        self.assertNotIn("get_polygon(i)", BODY)
        self.assertIn("const Vector3 *vertex_data = vertices.ptr();", BODY)

    def test_debug_geometry_materials_and_cache_remain(self):
        self.assertIn("if (debug_mesh.is_valid())", BODY)
        self.assertIn("RWLockRead read_lock(rwlock);", BODY)
        self.assertIn("Mesh::PRIMITIVE_TRIANGLES", BODY)
        self.assertIn("Mesh::PRIMITIVE_LINES", BODY)
        self.assertIn("get_debug_navigation_geometry_face_material()", BODY)
        self.assertIn("get_debug_navigation_geometry_edge_material()", BODY)


if __name__ == "__main__":
    unittest.main()
