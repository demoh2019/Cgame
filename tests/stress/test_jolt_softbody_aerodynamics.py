"""Jolt soft body aerodynamic drag and XPBD bending source/math contracts.

These lightweight checks do not replace native GDScript simulation and builds.
Run: python3 -m unittest tests/stress/test_jolt_softbody_aerodynamics.py -v
"""

import math
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
CPP = ROOT / "modules/jolt_physics/objects/jolt_soft_body_3d.cpp"
HEADER = ROOT / "modules/jolt_physics/objects/jolt_soft_body_3d.h"
SETTINGS = ROOT / "modules/jolt_physics/jolt_project_settings.cpp"


def drag_impulse(speed, area, inv_mass_sum, coeff, step):
    """Signed nodal impulse, clamped to avoid reversing mean normal velocity."""
    if speed == 0.0 or inv_mass_sum <= 0.0:
        return 0.0
    magnitude = min(
        coeff * area * (1.0 / 6.0) * speed * speed * step,
        3.0 * abs(speed) / inv_mass_sum,
    )
    return -math.copysign(magnitude, speed)


class JoltSoftBodyAerodynamicsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cpp = CPP.read_text(encoding="utf-8")
        cls.header = HEADER.read_text(encoding="utf-8")
        cls.settings = SETTINGS.read_text(encoding="utf-8")
        cls.forces = cls.cpp.split(
            "void JoltSoftBody3D::_apply_environmental_forces(float p_step) {", 1
        )[1].split("void JoltSoftBody3D::_update_mass()", 1)[0]
        cls.setter = cls.cpp.split("void JoltSoftBody3D::set_drag(float p_drag) {", 1)[1].split(
            "Variant JoltSoftBody3D::get_state(", 1
        )[0]

    def test_existing_default_does_not_traverse_cloth_for_drag(self):
        self.assertIn("float drag_coefficient = 0.0f;", self.header)
        self.assertIn("!wind_areas_scratch.is_empty() || drag_coefficient > 0.0f", self.forces)
        self.assertIn("if (drag_coefficient > 0.0f)", self.forces)
        self.assertEqual(self.forces.count("motion_properties.GetFaces()"), 1)

    def test_drag_uses_current_per_vertex_velocity_and_area(self):
        self.assertIn("physics_vertex0.mVelocity", self.forces)
        self.assertIn("physics_vertex1.mVelocity", self.forces)
        self.assertIn("physics_vertex2.mVelocity", self.forces)
        self.assertIn("normal.dot(average_velocity)", self.forces)
        self.assertIn("double(triangle_area) * (1.0 / 6.0)", self.forces)
        self.assertIn("inverse_mass_sum", self.forces)
        self.assertIn("impulse_per_vertex -= normal", self.forces)

    def test_drag_parameter_validates_and_roundtrips(self):
        self.assertIn("return drag_coefficient;", self.cpp)
        self.assertIn("p_drag < 0.0f || !Math::is_finite(p_drag)", self.setter)
        self.assertLess(
            self.setter.index("ERR_FAIL_COND_MSG"), self.setter.index("drag_coefficient = p_drag")
        )

    def test_opt_in_bending_supports_distance_and_dihedral(self):
        self.assertIn('soft_body_bend_mode", PROPERTY_HINT_ENUM, "Disabled,Distance,Dihedral"), 0', self.settings)
        self.assertIn("vertex_attrib.mBendCompliance", self.cpp)
        self.assertIn("BendType::Distance", self.cpp)
        self.assertIn("BendType::Dihedral", self.cpp)
        self.assertIn("CreateConstraints(&vertex_attrib, 1, bend_type)", self.cpp)

    def test_impulses_are_dissipative_and_capped(self):
        for speed in (-1000.0, -5.0, -0.1, 0.1, 5.0, 1000.0):
            for coeff in (0.0, 0.5, 1.5, 1000.0):
                with self.subTest(speed=speed, coefficient=coeff):
                    inverse_mass_sum = 4.0
                    impulse = drag_impulse(speed, 1.2, inverse_mass_sum, coeff, 1.0 / 60.0)
                    self.assertTrue(math.isfinite(impulse))
                    self.assertLessEqual(impulse * speed, 0.0)
                    self.assertLessEqual(
                        abs(impulse) * inverse_mass_sum / 3.0, abs(speed) + 1e-10
                    )
                    after = speed + impulse * inverse_mass_sum / 3.0
                    self.assertGreaterEqual(speed * after, -1e-10)

    def test_no_effect_for_zero_coefficient_or_area_or_speed(self):
        for speed, area, coeff in [(5, 1, 0), (5, 0, 1), (0, 1, 1)]:
            self.assertEqual(drag_impulse(speed, area, 3, coeff, 1 / 60), 0.0)


if __name__ == "__main__":
    unittest.main()
