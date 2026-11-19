"""Source-level contracts for closest-unused 3D manifold recycling.

Run with: python3 -m unittest tests/stress/test_physics_manifold_recycling.py
Runtime collision behavior is exercised separately by physics_manifold_3d_regression.gd.
"""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
SOURCE_3D = ROOT / "modules/godot_physics_3d/godot_body_pair_3d.cpp"


class ManifoldRecyclingContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        text = SOURCE_3D.read_text(encoding="utf-8")
        start = text.index("void GodotBodyPair3D::contact_added_callback(")
        end = text.index("// Figure out if the contact amount must be reduced", start)
        cls.matcher = text[start:end]

    def test_recycled_contact_is_nearest_and_unused(self):
        block = self.matcher
        self.assertIn("if (previous.used) {", block)
        self.assertIn("distance_A_squared + distance_B_squared", block)
        self.assertIn("total_distance_squared < best_distance_squared", block)
        self.assertIn("if (best_match != -1)", block)
        self.assertIn("Contact &previous = contacts[best_match];", block)

    def test_recycled_impulses_require_compatible_normal(self):
        block = self.matcher
        self.assertIn("previous.normal.dot(contact.normal) >= real_t(0.98)", block)
        self.assertIn("contact.acc_normal_impulse = previous.acc_normal_impulse;", block)
        self.assertIn("previous.acc_tangent_impulse.dot(contact.normal)", block)
        self.assertIn("previous = contact;", block)

    def test_match_can_be_used_only_once_per_pass(self):
        block = self.matcher
        self.assertIn("if (previous.used)", block)
        self.assertIn("contact.used = true;", block)
        self.assertIn("previous = contact;", block)


if __name__ == "__main__":
    unittest.main()
