"""Source-level invariants for the ImporterMesh memory/CPU fast paths."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SRC = (ROOT / "scene/resources/3d/importer_mesh.cpp").read_text(encoding="utf-8")
FACES = SRC.split("Vector<Face3> ImporterMesh::get_faces() const {", 1)[1].split("#ifndef PHYSICS_3D_DISABLED", 1)[0]
NAV = SRC.split("Ref<NavigationMesh> ImporterMesh::create_navigation_mesh() {", 1)[1].split("extern bool (*array_mesh_lightmap_unwrap_callback)", 1)[0]
MERGE = SRC.split("Ref<ImporterMesh> ImporterMesh::merge_importer_meshes(", 1)[1].split("Vector<Face3> ImporterMesh::get_faces()", 1)[0]
UNWRAP = SRC.split("Error ImporterMesh::lightmap_unwrap_cached(", 1)[1].split("void ImporterMesh::set_lightmap_size_hint(", 1)[0]


class MeshImporterFastPathContracts(unittest.TestCase):
    def test_navigation_faces_allocate_exactly_once(self):
        self.assertIn("faces.reserve_exact(face_count);", FACES)
        self.assertIn("face_count += indices.size() / 3;", FACES)
        self.assertIn("face_count += vertices.size() / 3;", FACES)

    def test_navigation_faces_use_read_only_buffer_pointers(self):
        self.assertIn("const Vector3 *vertex_ptr = vertices.ptr();", FACES)
        self.assertIn("const int *index_ptr = indices.ptr();", FACES)
        self.assertNotIn("Vector<Vector3> vertices = surfaces[i].arrays", FACES)

    def test_navigation_vertex_dedup_avoids_repeated_hash_lookups(self):
        self.assertIn("unique_vertices.getptr(v)", NAV)
        self.assertIn("unique_vertices.insert(v, idx);", NAV)
        self.assertNotIn("unique_vertices.has(v)", NAV)

    def test_merge_transforms_detach_each_packed_array_only_once(self):
        self.assertIn("Vector3 *vertices_write = vertices.is_empty() ? nullptr : vertices.ptrw();", MERGE)
        self.assertIn("Vector3 *normals_write = normals.is_empty() ? nullptr : normals.ptrw();", MERGE)
        self.assertIn("float *tangents_write = tangents.is_empty() ? nullptr : tangents.ptrw();", MERGE)
        self.assertNotIn("vertices.ptrw()[vertex_index]", MERGE)
        self.assertNotIn("tangents.ptrw()[tangent_index", MERGE)

    def test_merging_indices_uses_one_write_pointer(self):
        self.assertIn("int32_t *indices_write = incoming_indices.ptrw();", MERGE)
        self.assertIn("indices_write[i] += existing_vertex_count;", MERGE)
        self.assertNotIn("incoming_indices.ptrw()[i]", MERGE)

    def test_lightmap_unwrap_uses_readonly_packed_arrays_and_bulk_writes(self):
        self.assertIn("const PackedVector3Array rvertices", UNWRAP)
        self.assertIn("const PackedVector3Array rnormals", UNWRAP)
        self.assertIn("const PackedInt32Array rindices", UNWRAP)
        self.assertIn("const Vector3 *read_vertices = rvertices.ptr();", UNWRAP)
        self.assertIn("float *vertices_write = vertices.ptr() + vertex_ofs * 3;", UNWRAP)
        self.assertIn("Pair<int, int> *uv_indices_write = uv_indices.ptr() + vertex_ofs;", UNWRAP)

    def test_lightmap_surface_vertex_arrays_are_moved_not_copied(self):
        self.assertIn("lightmap_surfaces.reserve_exact(get_surface_count());", UNWRAP)
        self.assertIn("lightmap_surfaces.push_back(std::move(s));", UNWRAP)
        self.assertNotIn("lightmap_surfaces.push_back(s);", UNWRAP)

    def test_existing_vertex_compression_preservation_is_unchanged(self):
        self.assertIn("s.format |= (get_surface_format(i) & RSE::ARRAY_FLAG_COMPRESS_ATTRIBUTES);", UNWRAP)


if __name__ == "__main__":
    unittest.main()
