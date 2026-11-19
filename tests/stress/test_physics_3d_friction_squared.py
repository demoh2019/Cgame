"""Regression contracts for 3D rigid and rigid/soft friction fast paths.

These source and mathematical checks complement native physics integration tests.
"""
from pathlib import Path
import math
import unittest

SOURCE = Path(__file__).resolve().parents[2] / "modules/godot_physics_3d/godot_body_pair_3d.cpp"


def reference_clamp(magnitude: float, limit: float, epsilon: float = 1e-5) -> float:
    if magnitude > epsilon and magnitude > limit:
        return limit
    return magnitude


def optimized_clamp(magnitude: float, limit: float, epsilon: float = 1e-5) -> float:
    magnitude_squared = magnitude * magnitude
    if magnitude_squared > epsilon * epsilon and (limit < 0.0 or magnitude_squared > limit * limit):
        return limit
    return magnitude


class ContactFrictionFastPathContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source = SOURCE.read_text(encoding="utf-8")
        def section(start, end):
            pos = source.index(start)
            return source[pos:source.index(end, pos)]
        cls.soft_callback = section("void GodotBodySoftBodyPair3D::contact_added_callback(", "void GodotBodySoftBodyPair3D::validate_contacts(")
        cls.soft_solve = section("void GodotBodySoftBodyPair3D::solve(", "GodotBodySoftBodyPair3D::GodotBodySoftBodyPair3D(")
        cls.rigid_pre_solve = section("bool GodotBodyPair3D::pre_solve(", "void GodotBodyPair3D::solve(")
        cls.rigid_solve = section("void GodotBodyPair3D::solve(", "GodotBodyPair3D::GodotBodyPair3D(")

    def test_soft_contact_warmstart_requires_matching_normal(self):
        self.assertIn("c.index_B == p_index_B", self.soft_callback)
        self.assertIn("c.normal.dot(contact.normal) >= real_t(0.98)", self.soft_callback)
        self.assertIn("c.acc_tangent_impulse.dot(contact.normal)", self.soft_callback)

    def test_rigid_soft_friction_uses_squared_lengths(self):
        for code in (self.rigid_solve, self.soft_solve):
            with self.subTest(solver="soft" if code == self.soft_solve else "rigid"):
                self.assertIn("fi_len_squared = c.acc_tangent_impulse.length_squared()", code)
                self.assertIn("fi_len_squared > jtMax * jtMax", code)
                self.assertIn("Math::sqrt(fi_len_squared)", code)
                self.assertNotIn("real_t fi_len = c.acc_tangent_impulse.length()", code)

    def test_rigid_warmstart_avoids_unneeded_square_root(self):
        code = self.rigid_pre_solve
        self.assertIn("cached_tangent_length_squared = c.acc_tangent_impulse.length_squared()", code)
        self.assertIn("cached_tangent_length_squared > cached_tangent_limit * cached_tangent_limit", code)
        self.assertIn("Math::sqrt(cached_tangent_length_squared)", code)
        self.assertIn("cached_tangent_limit <= 0.0", code)
        self.assertNotIn("cached_tangent_length = c.acc_tangent_impulse.length()", code)

    def test_rigid_warmstart_clamp_matches_nonnegative_reference(self):
        for x, y, z in ((0.0, 0.0, 0.0), (0.1, -0.2, 0.3), (3.0, 4.0, 0.0), (1e-8, 2e-8, 0.0)):
            magnitude = math.sqrt(x * x + y * y + z * z)
            for limit in (0.0, 0.01, 0.5, 1.0, 10.0):
                reference_scale = 0.0 if limit <= 0 else (min(1.0, limit / magnitude) if magnitude > 0 else 1.0)
                length_sq = x * x + y * y + z * z
                optimized_scale = 0.0 if limit <= 0 else (limit / math.sqrt(length_sq) if length_sq > limit * limit else 1.0)
                with self.subTest(impulse=(x, y, z), limit=limit):
                    self.assertTrue(math.isclose(reference_scale, optimized_scale, rel_tol=1e-12, abs_tol=1e-12))

    def test_soft_signed_material_override_is_preserved(self):
        self.assertIn("jtMax < 0.0 || fi_len_squared > jtMax * jtMax", self.soft_solve)

    def test_squared_clamp_matches_reference(self):
        values = (0.0, 1e-7, 1e-5, 1e-4, 0.1, 0.5, 2.0)
        limits = (-1.0, -0.02, 0.0, 0.001, 0.3, 1.5)
        for value in values:
            for limit in limits:
                with self.subTest(value=value, limit=limit):
                    self.assertTrue(math.isclose(reference_clamp(value, limit),
                                                 optimized_clamp(value, limit),
                                                 rel_tol=1e-12, abs_tol=1e-12))


if __name__ == "__main__":
    unittest.main()
