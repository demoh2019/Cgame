"""Regression contracts for report-only contacts with zero inverse mass.

In Godot the contact-only path is used for non-responsive bodies that still
report contact points. The velocity solver must not invert their zero mass.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ReportOnlyContactContracts(unittest.TestCase):
    @staticmethod
    def pre_solve(dimension):
        source = (ROOT / "modules" / f"godot_physics_{dimension}" / f"godot_body_pair_{dimension}.cpp").read_text(encoding="utf-8")
        symbol = dimension.upper()
        start = source.index(f"bool GodotBodyPair{symbol}::pre_solve(")
        end = source.index(f"void GodotBodyPair{symbol}::solve(", start)
        return source[start:end]

    def test_2d_guarded_effective_mass_and_bias(self):
        source = self.pre_solve("2d")
        self.assertIn("if (!report_contacts_only) {\n\t\t\t// Precompute normal mass", source)
        self.assertIn("if (!report_contacts_only) {\n\t\t\t\tconst real_t rtA", source)
        self.assertIn("kNormal > 0.0 ? 1.0f / kNormal : 0.0f", source)
        self.assertIn("kTangent > 0.0 ? 1.0f / kTangent : 0.0f", source)
        self.assertIn("if (!report_contacts_only) {\n\t\t\tc.bias =", source)
        self.assertIn("if (report_contacts_only) {", source)

    def test_3d_guarded_effective_mass_and_bias(self):
        source = self.pre_solve("3d")
        self.assertIn("if (!report_contacts_only) {\n\t\t\t// Precompute normal mass", source)
        self.assertIn("kNormal > 0.0 ? 1.0f / kNormal : 0.0f", source)
        self.assertIn("if (report_contacts_only) {", source)
        self.assertIn("c.depth = depth;", source)


if __name__ == "__main__":
    unittest.main()
