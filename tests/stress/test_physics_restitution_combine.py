"""Source-contract regression checks for 2D/3D restitution mixing.

Native doctests in tests/servers cover the numerical rules. These tests verify
that the project-setting API and both contact solvers stay wired up.
"""

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class RestitutionMixSourceContracts(unittest.TestCase):
    def test_each_dimension_registers_and_reads_setting(self):
        for dim in ("2d", "3d"):
            with self.subTest(dim=dim):
                path = f"physics/{dim}/solver/restitution_combine_mode"
                server = (ROOT / f"servers/physics_{dim}/physics_server_{dim}.cpp").read_text(encoding="utf-8")
                space = (ROOT / f"modules/godot_physics_{dim}/godot_space_{dim}.cpp").read_text(encoding="utf-8")
                header = (ROOT / f"modules/godot_physics_{dim}/godot_space_{dim}.h").read_text(encoding="utf-8")
                self.assertIn(path, server)
                self.assertIn(path, space)
                self.assertIn("godot_physics_combine_restitution(p_a, p_b, restitution_combine_mode)", header)

    def test_rigid_contacts_reuse_pair_mix(self):
        for dim in ("2d", "3d"):
            with self.subTest(dim=dim):
                source = (ROOT / f"modules/godot_physics_{dim}/godot_body_pair_{dim}.cpp").read_text(encoding="utf-8")
                self.assertIn("const real_t mixed_restitution = space->mix_restitution(", source)
                self.assertIn("c.bounce = mixed_restitution;", source)
                self.assertNotIn("c.bounce = combine_bounce(A, B);", source)

    def test_native_modes_are_covered(self):
        header = (ROOT / "servers/physics_restitution_combine.h").read_text(encoding="utf-8")
        tests = (ROOT / "tests/servers/test_godot_physics_restitution_combine.cpp").read_text(encoding="utf-8")
        for mode in range(1, 6):
            self.assertIn(f"case {mode}:", header)
            self.assertIn(f"godot_physics_combine_restitution(a, b, {mode})", tests)
        self.assertIn("TEST_FORCE_LINK(test_godot_physics_restitution_combine)", tests)


if __name__ == "__main__":
    unittest.main()
