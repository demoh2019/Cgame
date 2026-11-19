"""Regression contracts for 3D persistent-contact warm starting.

These checks supplement (but do not replace) runtime physics tests. They ensure
cached impulses are gated by contact-normal coherence and that friction stays
tangential after the normal rotates.
"""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
SOURCE_2D = ROOT / "modules" / "godot_physics_2d" / "godot_body_pair_2d.cpp"
SOURCE_3D = ROOT / "modules" / "godot_physics_3d" / "godot_body_pair_3d.cpp"


class ContactWarmStartContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source = SOURCE_3D.read_text(encoding="utf-8")
        begin = source.index("void GodotBodyPair3D::contact_added_callback(")
        end = source.index("// Figure out if the contact amount must be reduced", begin)
        cls.reuse_block = source[begin:end]

    def test_same_normal_threshold_as_2d(self):
        block = self.reuse_block
        self.assertIn("if (c.normal.dot(contact.normal) >= real_t(0.98)) {", block)
        self.assertIn(
            "if (c.normal.dot(contact.normal) >= real_t(0.98)) {",
            SOURCE_2D.read_text(encoding="utf-8"),
        )

    def test_all_warmstart_impulses_are_guarded(self):
        block = self.reuse_block
        start = block.index("if (c.normal.dot(contact.normal) >= real_t(0.98)) {")
        end = block.index("\n\t\t\t}", start)
        guarded = block[start:end]
        for member in (
            "acc_normal_impulse",
            "acc_bias_impulse",
            "acc_bias_impulse_center_of_mass",
            "acc_tangent_impulse",
        ):
            self.assertIn(f"contact.{member} =", guarded)
            self.assertNotIn(f"contact.{member} =", block[end:])

    def test_reused_friction_is_projected_onto_new_contact_plane(self):
        block = self.reuse_block
        self.assertIn(
            "c.acc_tangent_impulse - contact.normal * c.acc_tangent_impulse.dot(contact.normal)",
            block,
        )

    def test_nearby_contacts_remain_matched_even_if_impulses_are_reset(self):
        block = self.reuse_block
        gate = block.index("if (c.normal.dot(contact.normal) >= real_t(0.98)) {")
        assignment = block.index("c = contact;", gate)
        ret = block.index("return;", assignment)
        self.assertLess(assignment, ret)


if __name__ == "__main__":
    unittest.main()
