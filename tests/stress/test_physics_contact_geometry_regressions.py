"""Source contracts for contact numerical stability.

The C++ doctests in tests/servers validate the actual contact calculations.
These checks ensure fast-path regressions stay wired up even on Python-only CI.
"""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]


class PhysicsContactGeometryRegression(unittest.TestCase):
    def test_3d_plane_margin_is_measured_in_world_space(self):
        source = (ROOT / "modules/godot_physics_3d/godot_collision_solver_3d.cpp").read_text(encoding="utf-8")
        begin = source.index("bool GodotCollisionSolver3D::solve_static_world_boundary(")
        end = source.index("bool GodotCollisionSolver3D::solve_separation_ray(", begin)
        routine = source[begin:end]
        self.assertIn("supports[i] = p_transform_B.xform(supports[i]) - p.normal * p_margin;", routine)
        self.assertNotIn("p_margin * supports[i].normalized()", routine)
        self.assertIn("p_result_callback(support_A, 0, supports[i], 0, -p.normal, p_userdata);", routine)

    def test_2d_pair_uses_fallback_for_coincident_contacts(self):
        source = (ROOT / "modules/godot_physics_2d/godot_body_pair_2d.cpp").read_text(encoding="utf-8")
        begin = source.index("void GodotBodyPair2D::_contact_added_callback(")
        end = source.index("void GodotBodyPair2D::_validate_contacts()", begin)
        routine = source[begin:end]
        self.assertIn("godot_physics_2d_contact_normal(p_point_A, p_point_B, -offset_B)", routine)
        self.assertNotIn("contact.normal = (p_point_A - p_point_B).normalized()", routine)

    def test_native_geometry_tests_registered(self):
        paths = [
            ("test_godot_physics_2d_contact_normal.cpp",
             "TEST_FORCE_LINK(test_godot_physics_2d_contact_normal)", "SUBCASE(", 5),
            ("test_godot_physics_3d_world_boundary_margin.cpp",
             "TEST_FORCE_LINK(test_godot_physics_3d_world_boundary_margin)", "TEST_CASE(", 2),
        ]
        for filename, registration, case_marker, minimum_cases in paths:
            with self.subTest(filename=filename):
                source = (ROOT / "tests/servers" / filename).read_text(encoding="utf-8")
                self.assertIn(registration, source)
                self.assertGreaterEqual(source.count(case_marker), minimum_cases)


if __name__ == "__main__":
    unittest.main()
