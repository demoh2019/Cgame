"""Contracts for low-allocation navigation polygon construction."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SRC = (ROOT / "scene/resources/navigation_mesh.cpp").read_text(encoding="utf-8")
BLOCK = SRC.split("void NavigationMesh::create_from_mesh(const Ref<Mesh> &p_mesh) {", 1)[1].split(
    "void NavigationMesh::set_sample_partition_type(", 1)[0]


class NavigationTriangleBuildContracts(unittest.TestCase):
    def test_polygon_vector_reserved_per_surface(self):
        self.assertIn("polygons.reserve_exact(polygons.size() + rlen / 3);", BLOCK)
        self.assertLess(BLOCK.index("polygons.reserve_exact("), BLOCK.index("for (int j = 0; j < rlen; j += 3)"))

    def test_each_polygon_is_owned_not_shared_with_mutable_scratch(self):
        self.assertIn("Vector<int> polygon;", BLOCK)
        self.assertIn("int *triangle = polygon.ptrw();", BLOCK)
        self.assertIn("polygons.push_back(std::move(polygon));", BLOCK)
        self.assertNotIn("polygon.write[", BLOCK)

    def test_malformed_index_counts_are_skipped_before_data_appending(self):
        self.assertIn("ERR_CONTINUE_MSG(rlen % 3 != 0", BLOCK)
        self.assertLess(BLOCK.index("ERR_CONTINUE_MSG(rlen % 3 != 0"), BLOCK.index("vertices.append_array(varr);"))

    def test_original_index_offset_and_triangle_order_remain(self):
        self.assertIn("const int from = vertices.size();", BLOCK)
        for k in range(3):
            self.assertIn(f"triangle[{k}] = indices[j + {k}] + from;", BLOCK)

    def test_empty_and_nontriangle_surfaces_still_skip(self):
        self.assertIn("surface_get_primitive_type(i) != Mesh::PRIMITIVE_TRIANGLES", BLOCK)
        self.assertIn("if (varr.is_empty() || iarr.is_empty())", BLOCK)
        self.assertIn("polygons.clear();", BLOCK)
        self.assertIn("vertices = Vector<Vector3>();", BLOCK)


if __name__ == "__main__":
    unittest.main()
