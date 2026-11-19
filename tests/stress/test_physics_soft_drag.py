"""Quadratic SoftBody3D aerodynamic drag regression contracts.

The native simulation test is physics_soft_drag_regression.gd; these
source and mathematical checks alone do not establish native correctness.
Run: python3 -m unittest discover -s tests/stress -p test_physics_soft_drag.py -v
"""

import math
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
CPP = ROOT / "modules/godot_physics_3d/godot_soft_body_3d.cpp"


def nodal_drag_force(normal_speed, area, coefficient):
    """Analytic two-sided face-normal drag distributed over three nodes."""
    return -coefficient * area * normal_speed * abs(normal_speed) / 6.0


class SoftBodyDragTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source = CPP.read_text(encoding="utf-8")

        def section(begin, end):
            start = source.index(begin)
            return source[start:source.index(end, start)]

        cls.forces = section(
            "void GodotSoftBody3D::apply_forces(",
            "Vector3 GodotSoftBody3D::_compute_area_windforce("
        )
        cls.predict = section(
            "void GodotSoftBody3D::predict_motion(",
            "void GodotSoftBody3D::solve_constraints("
        )
        cls.setter = section(
            "void GodotSoftBody3D::set_drag_coefficient(",
            "void GodotSoftBody3D::add_velocity("
        )

    def test_default_zero_drag_has_no_extra_face_work(self):
        self.assertIn("const bool apply_drag = drag_coefficient > 0.0;", self.forces)
        self.assertIn("if (!apply_pressure && !apply_wind && !apply_drag)", self.forces)
        self.assertIn("if (apply_drag && face.ra > CMP_EPSILON)", self.forces)
        self.assertIn("|| drag_coefficient > 0.0", self.predict)

    def test_drag_uses_face_normal_and_mean_node_velocity(self):
        self.assertIn("face.n[0]->v + face.n[1]->v + face.n[2]->v", self.forces)
        self.assertIn("face.normal.dot(face_velocity)", self.forces)
        self.assertIn("face.ra * real_t(1.0 / 6.0)", self.forces)
        self.assertIn("normal_speed * Math::abs(normal_speed)", self.forces)
        self.assertIn("node_force += face.normal * drag_per_node;", self.forces)

    def test_drag_is_fused_into_existing_face_force_pass(self):
        self.assertEqual(self.forces.count("for (const Face &face : faces)"), 1)
        self.assertIn("if (apply_wind || apply_drag)", self.forces)
        self.assertIn("face.n[j]->f += node_force;", self.forces)
        self.assertIn("if (apply_pressure)", self.forces)

    def test_drag_coefficient_is_validated(self):
        self.assertIn("p_val < 0.0 || !Math::is_finite(p_val)", self.setter)
        self.assertLess(self.setter.index("ERR_FAIL_COND_MSG"), self.setter.index("drag_coefficient = p_val;"))

    def test_force_is_dissipative_for_both_surface_sides(self):
        for velocity in (-30.0, -3.0, -0.1, 0.0, 0.1, 3.0, 30.0):
            with self.subTest(velocity=velocity):
                force = 3.0 * nodal_drag_force(velocity, area=2.0, coefficient=0.8)
                self.assertLessEqual(force * velocity, 0.0)
                self.assertTrue(math.isfinite(force))
                self.assertAlmostEqual(force, -0.5 * 0.8 * 2.0 * velocity * abs(velocity))

    def test_no_drag_when_coefficient_area_or_normal_speed_zero(self):
        for coefficient, area, normal_speed in ((0, 3, 5), (0.3, 0, 5), (0.3, 3, 0)):
            self.assertEqual(nodal_drag_force(normal_speed, area, coefficient), 0.0)

    def test_drag_scales_quadratically_with_velocity(self):
        first = nodal_drag_force(2.0, area=1.5, coefficient=0.7)
        faster = nodal_drag_force(4.0, area=1.5, coefficient=0.7)
        self.assertAlmostEqual(faster, 4.0 * first)


if __name__ == "__main__":
    unittest.main()
