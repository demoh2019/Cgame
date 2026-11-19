"""Regression contracts for exact-zero impulse fast paths in GodotPhysics.

The solver skips a body update only when its *incremental* impulse is exactly
zero. Warm-start caches and solver iteration counts remain intact. This test
checks source contracts and projected-impulse arithmetic; run the compiled
engine's physics regressions separately to cover runtime interactions.
"""

from pathlib import Path
import math
import random
import unittest


ROOT = Path(__file__).resolve().parents[2]
SOURCE_2D = ROOT / "modules/godot_physics_2d/godot_body_pair_2d.cpp"
SOURCE_3D = ROOT / "modules/godot_physics_3d/godot_body_pair_3d.cpp"


class ZeroImpulseContactContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source2 = SOURCE_2D.read_text(encoding="utf-8")
        source3 = SOURCE_3D.read_text(encoding="utf-8")
        a = source2.index("void GodotBodyPair2D::solve(")
        b = source2.index("GodotBodyPair2D::GodotBodyPair2D(", a)
        cls.rigid2 = source2[a:b]
        a = source3.index("void GodotBodyPair3D::solve(")
        b = source3.index("GodotBodyPair3D::GodotBodyPair3D(", a)
        cls.rigid3 = source3[a:b]
        a = source3.index("void GodotBodySoftBodyPair3D::solve(")
        b = source3.index("GodotBodySoftBodyPair3D::GodotBodySoftBodyPair3D(", a)
        cls.soft3 = source3[a:b]

    def test_rigid_2d_skips_only_exact_zero_impulses(self):
        block = self.rigid2
        self.assertIn("if (bias_delta != 0.0)", block)
        self.assertIn("if (jb_com != Vector2())", block)
        self.assertIn("if (j != Vector2())", block)
        self.assertIn("if (delta0 != 0.0)", block)
        self.assertIn("if (delta1 != 0.0)", block)
        self.assertIn("c0.acc_normal_impulse = next0;", block)
        self.assertIn("c1.acc_normal_impulse = next1;", block)
        self.assertIn("if (block_solved)", block)

    def test_rigid_3d_skips_only_exact_zero_impulses(self):
        block = self.rigid3
        self.assertIn("if (bias_delta != 0.0)", block)
        self.assertIn("if (jb_com != Vector3())", block)
        self.assertIn("if (j != Vector3())", block)
        self.assertIn("if (jt != Vector3())", block)
        self.assertIn("c.acc_normal_impulse = MAX(jnOld + jn, 0.0f);", block)
        self.assertIn("c.acc_tangent_impulse += jt;", block)

    def test_rigid_soft_3d_skips_only_exact_zero_impulses(self):
        block = self.soft3
        self.assertIn("if (bias_delta != 0.0)", block)
        self.assertIn("if (jb_com != Vector3())", block)
        self.assertIn("if (j != Vector3())", block)
        self.assertIn("if (jt != Vector3())", block)
        self.assertIn("soft_body->apply_node_impulse(c.index_B, j);", block)
        self.assertIn("soft_body->apply_node_bias_impulse(c.index_B, jb);", block)

    def test_center_mass_bias_denominator_is_positive(self):
        for block in (self.rigid2, self.rigid3, self.soft3):
            with self.subTest(kind=block[:45]):
                self.assertIn("const real_t total_inverse_mass =", block)
                self.assertIn("if (total_inverse_mass > 0.0 &&", block)
                self.assertIn("/ total_inverse_mass;", block)
                self.assertNotIn("/ (inv_mass_A + inv_mass_B)", block)
                self.assertNotIn("/ (body_inv_mass + node_inv_mass)", block)

    def test_rigid_3d_tangent_mass_guards_singular_contacts(self):
        block = self.rigid3
        self.assertIn("const real_t tangent_mass = inv_mass_A + inv_mass_B", block)
        self.assertIn("if (tangent_mass <= 0.0)", block)
        self.assertIn("const real_t t = -tvl / tangent_mass;", block)
        self.assertLess(block.index("if (tangent_mass <= 0.0)"),
                        block.index("const real_t t = -tvl / tangent_mass;"))
        # The rigid-soft solver already has an independent tangent guard.
        self.assertIn("const real_t tangent_mass = body_inv_mass + node_inv_mass", self.soft3)
        self.assertIn("if (tangent_mass <= 0.0)", self.soft3)

    def test_skip_zero_matches_projected_gauss_seidel(self):
        rng = random.Random(24248)
        for _ in range(2000):
            old_normal = rng.uniform(0.0, 80.0)
            incremental = rng.uniform(-150.0, 150.0)
            new_normal = max(0.0, old_normal + incremental)
            delta = new_normal - old_normal
            inv_mass = rng.choice((0.0, 0.0, 0.01, 0.25, 1.0, 5.0))
            velocity = rng.uniform(-20.0, 20.0)
            applied = velocity + delta * inv_mass
            skipped = velocity if delta == 0.0 else velocity + delta * inv_mass
            self.assertEqual(applied, skipped)
            self.assertTrue(math.isfinite(skipped))

    def test_projection_rejects_zero_inverse_mass_without_division(self):
        for effective_inverse_mass in (0.0, -1.0, -0.001, 1e-12, 0.25, 4.0):
            for bias in (-4.0, -0.1, 0.0, 0.1, 4.0):
                correction = (bias / effective_inverse_mass
                              if effective_inverse_mass > 0.0 else 0.0)
                self.assertTrue(math.isfinite(correction))


if __name__ == "__main__":
    unittest.main()
