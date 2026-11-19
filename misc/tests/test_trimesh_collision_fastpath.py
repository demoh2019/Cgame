"""Contracts for exact-size, single-write concave collision mesh generation."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SRC = (ROOT / "scene/resources/mesh.cpp").read_text(encoding="utf-8")
BLOCK = SRC.split("Ref<ConcavePolygonShape3D> Mesh::create_trimesh_shape() const {", 1)[1].split(
    "Ref<Mesh> Mesh::create_outline(", 1)[0]


class TrimeshCollisionFastPathTests(unittest.TestCase):
    def test_exact_buffer_size_and_single_write_pointer(self):
        self.assertIn("face_points.resize(faces.size() * 3);", BLOCK)
        self.assertEqual(BLOCK.count("face_points.ptrw()"), 1)
        self.assertNotIn("face_points.set(", BLOCK)

    def test_face_data_read_by_pointer_without_struct_copies(self):
        self.assertIn("const Face3 *face_read = faces.ptr();", BLOCK)
        self.assertIn("const Face3 &face = face_read[i];", BLOCK)
        self.assertNotIn("faces.get(", BLOCK)

    def test_contiguous_triangle_layout_is_preserved(self):
        for index in range(3):
            self.assertIn(f"face_write[offset + {index}] = face.vertex[{index}];", BLOCK)
        self.assertIn("const int offset = i * 3;", BLOCK)

    def test_empty_mesh_and_shape_registration_remain(self):
        self.assertIn("if (faces.is_empty())", BLOCK)
        self.assertIn("Ref<ConcavePolygonShape3D> shape = memnew(ConcavePolygonShape3D);", BLOCK)
        self.assertIn("shape->set_faces(face_points);", BLOCK)


if __name__ == "__main__":
    unittest.main()
