"""Source contracts for debug mesh generation without repeated CowData writes."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SOURCE = (ROOT / "scene/resources/mesh.cpp").read_text(encoding="utf-8")
LINES = SOURCE.split("void Mesh::generate_debug_mesh_lines(Vector<Vector3> &r_lines) {", 1)[1].split(
    "void Mesh::generate_debug_mesh_indices(", 1)[0]
INDICES = SOURCE.split("void Mesh::generate_debug_mesh_indices(Vector<Vector3> &r_points) {", 1)[1].split(
    "Vector<Vector3> Mesh::_get_faces()", 1)[0]


class DebugMeshFastPathContracts(unittest.TestCase):
    def test_debug_edges_use_single_writable_pointer(self):
        self.assertIn("Vector3 *lines_write = debug_lines.ptrw();", LINES)
        self.assertNotIn("debug_lines.write[", LINES)
        self.assertIn("const Vector3 &v0", LINES)
        self.assertIn("const Vector3 &v1", LINES)
        self.assertIn("const Vector3 &v2", LINES)

    def test_edge_topology_stays_three_pairs_per_triangle(self):
        self.assertIn("debug_lines.resize(tm->get_triangles().size() * 6);", LINES)
        for i, v in enumerate(["v0", "v1", "v1", "v2", "v2", "v0"]):
            self.assertIn(f"lines_write[j + {i}] = {v};", LINES)

    def test_cached_debug_lines_fast_path_is_preserved(self):
        self.assertIn("if (debug_lines.size() > 0)", LINES)
        self.assertIn("r_lines = debug_lines;", LINES)

    def test_indices_return_vector_by_cow_assignment(self):
        self.assertIn("r_points = tm->get_vertices();", INDICES)
        self.assertNotIn("r_points.resize(", INDICES)
        self.assertNotIn("r_points.write[", INDICES)


if __name__ == "__main__":
    unittest.main()
