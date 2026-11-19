"""Source/API wiring contracts for bounded GodotPhysics3D soft-body self collision.

Numerical closest-point and mass-weighted projection cases run in native
tests/servers/test_physics_softbody_self_collision.cpp. These checks do not
compile the engine or establish frame-rate improvements.
"""

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
DEFS = ROOT / "servers/physics_3d/physics_server_3d.cpp"
SPACE_CPP = ROOT / "modules/godot_physics_3d/godot_space_3d.cpp"
SPACE_H = ROOT / "modules/godot_physics_3d/godot_space_3d.h"
SOFT_CPP = ROOT / "modules/godot_physics_3d/godot_soft_body_3d.cpp"
SOFT_H = ROOT / "modules/godot_physics_3d/godot_soft_body_3d.h"
MATH = ROOT / "servers/physics_softbody_self_collision.h"
NATIVE = ROOT / "tests/servers/test_physics_softbody_self_collision.cpp"
STANDALONE = ROOT / "tests/stress/physics_softbody_edge_standalone.cpp"
VECTOR3_MOCK = ROOT / "tests/stress/mock_physics/core/math/vector3.h"


class SoftBodySelfCollisionSourceContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.defs = DEFS.read_text(encoding="utf-8")
        cls.space_cpp = SPACE_CPP.read_text(encoding="utf-8")
        cls.space_h = SPACE_H.read_text(encoding="utf-8")
        cls.soft_cpp = SOFT_CPP.read_text(encoding="utf-8")
        cls.soft_h = SOFT_H.read_text(encoding="utf-8")
        cls.math = MATH.read_text(encoding="utf-8")
        cls.native = NATIVE.read_text(encoding="utf-8")
        cls.standalone = STANDALONE.read_text(encoding="utf-8")
        cls.vector3_mock = VECTOR3_MOCK.read_text(encoding="utf-8")

    def test_world_configuration_is_default_disabled(self):
        self.assertIn('"physics/3d/solver/soft_body_self_collision_thickness"', self.defs)
        self.assertIn('"physics/3d/solver/soft_body_self_collision_compliance"', self.defs)
        self.assertIn('0.0);', self.defs)
        self.assertIn('GLOBAL_GET("physics/3d/solver/soft_body_self_collision_thickness")', self.space_cpp)
        self.assertIn('GLOBAL_GET("physics/3d/solver/soft_body_self_collision_compliance")', self.space_cpp)
        self.assertIn('Math::is_finite(configured_self_thickness)', self.space_cpp)
        self.assertIn('Math::is_finite(configured_self_compliance)', self.space_cpp)
        self.assertIn("get_soft_body_self_collision_thickness()", self.space_h)
        self.assertIn("get_soft_body_self_collision_compliance()", self.space_h)
        self.assertIn('"physics/3d/solver/soft_body_self_collision_edge_contacts"), false)', self.defs)
        self.assertIn('GLOBAL_GET("physics/3d/solver/soft_body_self_collision_edge_contacts")', self.space_cpp)
        self.assertIn("are_soft_body_self_collision_edge_contacts_enabled()", self.space_h)
        self.assertNotIn("GLOBAL_GET(", self.soft_cpp)
        self.assertIn("if (self_thickness > 0.0 && p_delta > 0.0)", self.soft_cpp)

    def test_bvh_broadphase_and_topology_exclusions(self):
        code = self.soft_cpp
        self.assertIn("initialize_self_collision_adjacency()", code)
        self.assertIn("self_collision_structural_edges.insert(key);", code)
        self.assertIn("adjacent == vertex->index", code)
        self.assertIn("structural_edges->has(_soft_body_edge_key(adjacent, vertex->index))", code)
        self.assertIn("face_tree.aabb_query(AABB(node.x - reach", code)
        self.assertIn("physics_softbody_closest_triangle_point(", code)
        self.assertIn("d2 == distances[insert] && face->index > indices[insert]", code)
        self.assertIn("MAX_CONTACTS_PER_VERTEX = 4", code)
        self.assertIn("MAX_TOTAL_CONTACTS = 65536", code)
        self.assertIn("MAX_FACES_PER_VERTEX = 128", code)
        self.assertIn("MAX_NARROWPHASE_FACES_PER_STEP = 1048576", code)
        self.assertIn("if (examined >= MAX_FACES_PER_VERTEX || *remaining_tests == 0)", code)
        self.assertIn("if (self_collision_contacts.size() >= MAX_TOTAL_CONTACTS || remaining_face_tests == 0)", code)

    def test_contacts_are_deferred_until_after_bvh_candidate_gather(self):
        source = self.soft_cpp
        start = source.index("void GodotSoftBody3D::solve_self_collisions(")
        end = source.index("void GodotSoftBody3D::solve_constraints(", start)
        method = source[start:end]
        self.assertIn("self_collision_contacts.clear();", method)
        self.assertIn("initialize_face_tree();", method)
        self.assertIn("update_face_tree(0.0);", method)
        self.assertLess(method.index("face_tree.aabb_query("), method.index("for (const SelfCollisionContact &contact"))
        self.assertIn("physics_softbody_project_self_contact(", method)
        self.assertIn("point.q);", method)
        self.assertLess(source.index("solve_self_collisions(self_thickness", end), source.index("const real_t vc =", end))
        self.assertIn("self_collision_contacts.reset();", source)
        self.assertIn("self_collision_adjacency_built = false;", source)

    def test_projection_validates_pins_degenerate_and_nonfinite(self):
        self.assertIn("physics_softbody_closest_triangle_point(", self.math)
        self.assertIn("const real_t weighted_mass = p_inv_mass_point +", self.math)
        self.assertIn("p_inv_mass_point < 0.0", self.math)
        self.assertIn("!(area_sq > CMP_EPSILON * CMP_EPSILON)", self.math)
        self.assertIn("p_previous_point - closest", self.math)
        self.assertIn("!next_point.is_finite()", self.math)
        for name in ("Voronoi regions", "pinned triangle", "pinned vertices", "invalid and degenerate"):
            self.assertIn(name.lower(), self.native.lower())


    def test_edge_edge_contacts_are_opt_in_and_use_face_bvh(self):
        source = self.soft_cpp
        self.assertIn("struct SelfCollisionEdge", self.soft_h)
        self.assertIn("struct SelfEdgeContact", self.soft_h)
        self.assertIn("LocalVector<SelfCollisionEdge> self_collision_edges;", self.soft_h)
        self.assertIn("LocalVector<SelfEdgeContact> self_collision_edge_contacts;", self.soft_h)
        self.assertIn("if (get_space()->are_soft_body_self_collision_edge_contacts_enabled())", source)
        self.assertIn("solve_self_edge_contacts(p_thickness, p_alpha_tilde);", source)
        self.assertIn("self_collision_edges_built = include_edges;", source)
        self.assertIn("if (!self_collision_structural_edges.has(key))", source)
        self.assertIn("face_tree.aabb_query(query_aabb, query);", source)
        self.assertIn("MAX_CONTACTS_PER_EDGE = 2", source)
        self.assertIn("MAX_TOTAL_EDGE_CONTACTS = 32768", source)
        self.assertIn("MAX_EDGE_TESTS_PER_SOURCE = 128", source)
        self.assertIn("MAX_EDGE_TESTS_PER_STEP = 1048576", source)
        self.assertIn("key <= source_key", source)
        self.assertIn("structural_edges->has(_soft_body_edge_key(a, c))", source)
        self.assertIn("self_collision_edge_contacts.reset();", source)
        self.assertIn("self_collision_edges.reset();", source)

    def test_edge_edge_projects_only_after_candidate_collection(self):
        method_start = self.soft_cpp.index("void GodotSoftBody3D::solve_self_edge_contacts(")
        method_end = self.soft_cpp.index("void GodotSoftBody3D::solve_constraints(", method_start)
        code = self.soft_cpp[method_start:method_end]
        self.assertLess(code.index("face_tree.aabb_query(query_aabb, query);"),
                        code.index("for (const SelfEdgeContact &contact"))
        self.assertIn("physics_softbody_closest_segment_points(", code)
        self.assertIn("physics_softbody_project_edge_contact(", code)
        self.assertIn("a.q, b.q, c.q, d.q);", code)
        self.assertIn("update_face_tree(0.0);", code)
        self.assertIn("if (self_collision_edge_contacts.size() >= MAX_TOTAL_EDGE_CONTACTS || remaining_tests == 0)", code)

    def test_segment_projection_has_mass_weighted_finite_safety(self):
        self.assertIn("physics_softbody_closest_segment_points(", self.math)
        self.assertIn("physics_softbody_project_edge_contact(", self.math)
        self.assertIn("double(p_inv_mass_a) * double(u) * double(u)", self.math)
        self.assertIn("old_separation.dot(normal) < 0.0", self.math)
        self.assertIn("if (!next_a.is_finite()", self.math)
        for name in ("crossed segments with distant endpoints",
                     "finite segments handle skew and parallel edges",
                     "compliance and pinned particles",
                     "degeneracy and invalid inputs"):
            self.assertIn(name.lower(), self.native.lower())

    def test_standalone_cpp_compiler_smoke_covers_exact_header_and_previous_math(self):
        self.assertIn('#include "servers/physics_softbody_self_collision.h"', self.standalone)
        self.assertIn("for (int iteration = 0; iteration < 20000 && ok; ++iteration)", self.standalone)
        self.assertIn("physics_softbody_closest_segment_points(", self.standalone)
        self.assertIn("physics_softbody_project_edge_contact(", self.standalone)
        self.assertIn("physics_softbody_project_self_contact(", self.standalone)
        self.assertIn("struct Vector3", self.vector3_mock)
        self.assertIn("constexpr Vector3", self.vector3_mock)


if __name__ == "__main__":
    unittest.main()
