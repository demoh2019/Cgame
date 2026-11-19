"""SoftBody3D wind attenuation and live mass/stiffness source regressions.

Run: python3 -m unittest discover -s tests/stress -p 'test_physics_soft_material_wind.py'

Includes a scalar reference model to cover facing/behind-source wind, default
zero falloff and degenerate spring/mass input. A native physics scene remains
necessary for verifying runtime C++ behavior.
"""

from pathlib import Path
import math
import unittest


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "modules/godot_physics_3d/godot_soft_body_3d.cpp"


def wind_attenuation(displacement, falloff):
    if falloff == 0.0:
        return 1.0
    distance_squared = max(sum(component * component for component in displacement), 1.0)
    return math.pow(distance_squared, -falloff * 0.5)


class SoftBodyMaterialAndWindContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source = SOURCE.read_text(encoding="utf-8")
        def section(start, end):
            begin = source.index(start)
            return source[begin:source.index(end, begin)]
        cls.update_links = section("void GodotSoftBody3D::update_link_constants(", "void GodotSoftBody3D::apply_nodes_transform(")
        cls.set_mass = section("void GodotSoftBody3D::set_total_mass(", "void GodotSoftBody3D::set_collision_margin(")
        cls.set_stiffness = section("void GodotSoftBody3D::set_linear_stiffness(", "void GodotSoftBody3D::set_shrinking_factor(")
        cls.wind = section("Vector3 GodotSoftBody3D::_compute_area_windforce(", "void GodotSoftBody3D::predict_motion(")
        cls.solve_links = section("void GodotSoftBody3D::solve_links(", "struct AABBQueryResult")

    def test_zero_stiffness_has_no_inverse_division(self):
        self.assertIn("if (!(linear_stiffness > 0.0))", self.update_links)
        self.assertIn("link.c0 = 0.0;", self.update_links)
        self.assertLess(self.update_links.index("if (!(linear_stiffness > 0.0))"),
                        self.update_links.index("1.0 / linear_stiffness"))
        self.assertIn("if (link.c0 > 0)", self.solve_links)

    def test_non_finite_or_non_positive_mass_rejected_before_division(self):
        self.assertIn("!(p_val > 0.0) || !Math::is_finite(p_val)", self.set_mass)
        self.assertLess(self.set_mass.index("Math::is_finite(p_val)"),
                        self.set_mass.index("1.0 / p_val"))

    def test_mass_update_preserves_deformed_rest_shape(self):
        self.assertIn("update_link_constants();", self.set_mass)
        self.assertNotIn("update_constants();", self.set_mass)
        self.assertNotIn("reset_link_rest_lengths();", self.set_mass)

    def test_live_stiffness_refreshes_solver_coefficients(self):
        self.assertIn("linear_stiffness = p_val;", self.set_stiffness)
        self.assertIn("update_link_constants();", self.set_stiffness)
        self.assertNotIn("reset_link_rest_lengths();", self.set_stiffness)

    def test_wind_skips_pow_for_default_zero_attenuation(self):
        self.assertIn("if (falloff != 0.0)", self.wind)
        self.assertIn("distance.length_squared()", self.wind)
        self.assertIn("std::pow(distance_squared, -falloff * real_t(0.5))", self.wind)
        self.assertNotIn("std::pow(projection_toward_centroid", self.wind)

    def test_wind_attenuation_is_finite_near_and_behind_source(self):
        for falloff in (0.0, 0.5, 1.0, 2.0):
            for displacement in ((0.0, 0.0, 0.0), (0.0, 0.0, -3.0),
                                 (0.0, 0.0, 3.0), (3.0, 4.0, -12.0)):
                with self.subTest(falloff=falloff, displacement=displacement):
                    self.assertTrue(math.isfinite(wind_attenuation(displacement, falloff)))
                    self.assertEqual(wind_attenuation(displacement, falloff),
                                     wind_attenuation(tuple(-v for v in displacement), falloff))

    def test_wind_matches_expected_inverse_distance(self):
        self.assertAlmostEqual(wind_attenuation((3.0, 4.0, 0.0), 1.0), 0.2)
        self.assertAlmostEqual(wind_attenuation((3.0, 4.0, 0.0), 2.0), 0.04)
        self.assertEqual(wind_attenuation((0.0, 0.0, 0.0), 2.0), 1.0)
        self.assertEqual(wind_attenuation((1e5, 0.0, 0.0), 0.0), 1.0)


if __name__ == "__main__":
    unittest.main()
