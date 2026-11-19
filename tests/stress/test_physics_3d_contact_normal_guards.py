"""Regression checks for degenerate 3D collision manifolds.

Native math and physics semantics are checked by the companion C++ doctests;
these source contracts prevent reintroducing the zero-depth SAT division.
"""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]


class ContactNormalGuards(unittest.TestCase):
    def test_sat_contact_retest_avoids_division_by_zero(self):
        source = (ROOT / "modules/godot_physics_3d/godot_collision_solver_3d_sat.cpp").read_text(encoding="utf-8")
        begin = source.index("static _FORCE_INLINE_ void test_contact_points(")
        end = source.index("_FORCE_INLINE_ void generate_contacts()", begin)
        routine = source[begin:end]
        self.assertIn("if (depth > CMP_EPSILON &&", routine)
        self.assertIn("separator->test_axis(axis / depth);", routine)
        self.assertLess(routine.index("if (depth > CMP_EPSILON &&"), routine.index("separator->test_axis(axis / depth);"))

    def test_rigid_pairs_use_zero_safe_normal_helper(self):
        source = (ROOT / "modules/godot_physics_3d/godot_body_pair_3d.cpp").read_text(encoding="utf-8")
        begin = source.index("void GodotBodyPair3D::contact_added_callback(")
        end = source.index("void GodotBodyPair3D::validate_contacts()", begin)
        routine = source[begin:end]
        self.assertIn("contact.normal = godot_physics_3d_contact_normal(", routine)
        self.assertNotIn("contact.normal = (p_point_A - p_point_B).normalized()", routine)

    def test_native_contact_normal_cases_registered(self):
        source = (ROOT / "tests/servers/test_godot_physics_3d_contact_normal.cpp").read_text(encoding="utf-8")
        self.assertIn("TEST_FORCE_LINK(test_godot_physics_3d_contact_normal)", source)
        self.assertIn("#ifdef MODULE_GODOT_PHYSICS_3D_ENABLED", source)
        self.assertGreaterEqual(source.count("SUBCASE("), 5)


if __name__ == "__main__":
    unittest.main()
