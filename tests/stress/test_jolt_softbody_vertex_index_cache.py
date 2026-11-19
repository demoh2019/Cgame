"""Jolt SoftBody3D mesh conversion: cache repeated mesh-index lookups.

Checks the source's two-level mapping and compares the optimized algorithm
with the original position-dedup algorithm for randomized indexed meshes.
Runtime Jolt cloth construction is validated by the native GDScript fixture.
"""

from pathlib import Path
import random
import unittest


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "modules/jolt_physics/objects/jolt_soft_body_3d.cpp"
STRESS = ROOT / "tests/stress/physics_jolt_softbody_vertex_dedup_regression.gd"


def old_mapping(vertices, corners):
    """Original per-corner position hash lookup, preserving encounter order."""
    positions = {}
    mesh_map = [-1] * len(vertices)
    faces = []
    for base in range(0, len(corners), 3):
        face = []
        for mesh_index in corners[base:base + 3]:
            vertex = vertices[mesh_index]
            if vertex not in positions:
                positions[vertex] = len(positions)
            index = positions[vertex]
            mesh_map[mesh_index] = index
            face.append(index)
        if len(set(face)) == 3:
            faces.append(tuple(reversed(face)))
    return mesh_map, faces, len(positions), len(corners)


def cached_mapping(vertices, corners):
    """New fast path hashes only the first use of a mesh index."""
    positions = {}
    mesh_map = [-1] * len(vertices)
    faces = []
    hash_lookups = 0
    for base in range(0, len(corners), 3):
        face = []
        for mesh_index in corners[base:base + 3]:
            index = mesh_map[mesh_index]
            if index == -1:
                hash_lookups += 1
                vertex = vertices[mesh_index]
                if vertex not in positions:
                    positions[vertex] = len(positions)
                index = positions[vertex]
                mesh_map[mesh_index] = index
            face.append(index)
        if len(set(face)) == 3:
            faces.append(tuple(reversed(face)))
    return mesh_map, faces, len(positions), hash_lookups


class JoltSoftBodyVertexIndexCacheTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = SOURCE.read_text(encoding="utf-8")
        cls.mesh = cls.source.split(
            "JPH::SoftBodySharedSettings *JoltSoftBody3D::_create_shared_settings() {", 1
        )[1].split("\nvoid JoltSoftBody3D::", 1)[0]

    def test_compact_contiguous_position_index(self):
        self.assertIn('#include "core/templates/a_hash_map.h"', self.source)
        self.assertIn("AHashMap<Vector3, int> vertex_to_physics;", self.mesh)
        self.assertNotRegex(self.mesh, r"(?<!A)HashMap<Vector3, int>")
        self.assertIn("max_referenced_vertices = MIN(", self.mesh)
        self.assertIn("vertex_to_physics.reserve(max_referenced_vertices + max_referenced_vertices / 2 + 1);", self.mesh)

    def test_mesh_index_fast_path_precedes_position_hash(self):
        code = self.mesh
        self.assertIn("int physics_index = mesh_to_physics[mesh_index];", code)
        self.assertIn("if (physics_index == -1) {", code)
        self.assertIn("const int *existing_index = vertex_to_physics.getptr(vertex);", code)
        self.assertIn("if (existing_index != nullptr) {", code)
        self.assertIn("physics_index = *existing_index;", code)
        self.assertIn("vertex_to_physics.insert(vertex, physics_index);", code)
        self.assertIn("mesh_to_physics[mesh_index] = physics_index;", code)
        self.assertIn("physics_face[j] = physics_index;", code)
        self.assertLess(code.index("int physics_index = mesh_to_physics[mesh_index];"), code.index("vertex_to_physics.getptr(vertex);"))
        self.assertLess(code.index("vertex_to_physics.getptr(vertex);"), code.index("mesh_to_physics[mesh_index] = physics_index;"))

    def test_mesh_face_winding_and_vertex_positions_preserved(self):
        code = self.mesh
        self.assertIn("physics_faces.emplace_back((JPH::uint32)physics_face[2], (JPH::uint32)physics_face[1], (JPH::uint32)physics_face[0]);", code)
        self.assertIn("physics_face[0] == physics_face[1]", code)
        self.assertIn("vertex.x - body_position.GetX()", code)
        self.assertIn("vertex.y - body_position.GetY()", code)
        self.assertIn("vertex.z - body_position.GetZ()", code)
        self.assertIn("pin_vertices(*this, pinned_vertices, mesh_to_physics, physics_vertices);", code)

    def test_random_meshes_match_original_position_dedup(self):
        rng = random.Random(20261119)
        for trial in range(400):
            vertex_count = rng.randint(4, 180)
            positions = [(rng.randrange(13), rng.randrange(15), rng.randrange(17)) for _ in range(vertex_count)]
            corners = [rng.randrange(vertex_count) for _ in range(3 * rng.randint(1, 250))]
            before = old_mapping(positions, corners)
            after = cached_mapping(positions, corners)
            with self.subTest(trial=trial):
                self.assertEqual(before[:3], after[:3])
                self.assertEqual(after[3], len(set(corners)))
                self.assertLessEqual(after[3], before[3])

    def test_dense_indexed_grid_avoids_most_hash_lookups(self):
        side = 32
        vertices = [(x, 0, y) for y in range(side) for x in range(side)]
        corners = []
        for y in range(side - 1):
            for x in range(side - 1):
                i = y * side + x
                corners.extend([i, i + side, i + 1, i + 1, i + side, i + side + 1])
        before = old_mapping(vertices, corners)
        after = cached_mapping(vertices, corners)
        self.assertEqual(before[:3], after[:3])
        self.assertEqual(after[3], side * side)
        self.assertLess(after[3] * 4, before[3])

    def test_native_fixture_stresses_welded_vertices_and_cleanup(self):
        gd = STRESS.read_text(encoding="utf-8")
        self.assertIn("const GRID := 24", gd)
        self.assertIn("const WAVES := 3", gd)
        self.assertIn("const BODIES_PER_WAVE := 3", gd)
        self.assertIn("PhysicsServer3D.soft_body_set_mesh", gd)
        self.assertIn("PhysicsServer3D.soft_body_get_point_global_position", gd)
        self.assertIn("max_duplicate_vertex_distance", gd)
        self.assertIn("JOLT_SOFTBODY_VERTEX_DEDUP_RESULT:", gd)
        self.assertIn("Jolt soft-body vertex dedup regression passed.", gd)


if __name__ == "__main__":
    unittest.main()
