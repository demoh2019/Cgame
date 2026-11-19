"""2D contact block-matrix cache invariants and LCP reference cases.

These are source contracts plus a pure-Python numerical reference for the
2-contact complementarity problem. They do NOT compile or run GodotPhysics;
use physics_block_solver_regression.gd for runtime engine coverage.
"""

from pathlib import Path
import random
import unittest


ROOT = Path(__file__).resolve().parents[2]
PAIR_CPP = ROOT / "modules" / "godot_physics_2d" / "godot_body_pair_2d.cpp"
PAIR_H = ROOT / "modules" / "godot_physics_2d" / "godot_body_pair_2d.h"


def reference_two_contact_lcp(k00, k01, k11, b0, b1):
    """Enumerate the four 2D LCP active sets as the C++ solver does."""
    determinant = k00 * k11 - k01 * k01
    assert k00 > 0 and k11 > 0 and determinant > 0
    x0 = -(k11 * b0 - k01 * b1) / determinant
    x1 = -(k00 * b1 - k01 * b0) / determinant
    if x0 >= 0 and x1 >= 0:
        return x0, x1
    x0, x1 = 0.0, -b1 / k11
    if x1 >= 0 and k01 * x1 + b0 >= 0:
        return x0, x1
    x0, x1 = -b0 / k00, 0.0
    if x0 >= 0 and k01 * x0 + b1 >= 0:
        return x0, x1
    if b0 >= 0 and b1 >= 0:
        return 0.0, 0.0
    raise AssertionError("SPD LCP did not find a solution")


class CachedBlockSolverContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cpp = PAIR_CPP.read_text(encoding="utf-8")
        cls.header = PAIR_H.read_text(encoding="utf-8")
        a = cls.cpp.index("bool GodotBodyPair2D::pre_solve(")
        b = cls.cpp.index("void GodotBodyPair2D::solve(", a)
        c = cls.cpp.index("GodotBodyPair2D::GodotBodyPair2D(", b)
        cls.pre_solve = cls.cpp[a:b]
        cls.solve = cls.cpp[b:c]

    def test_matrix_cache_lives_per_pair_not_per_contact(self):
        for name in ("block_k00", "block_k01", "block_k11",
                     "block_inv_determinant", "block_normal_valid"):
            self.assertIn(name, self.header)
        # One cache shared between two manifold contact points.
        self.assertEqual(self.header.count("real_t block_k00"), 1)

    def test_pre_solve_builds_conditioned_matrix_once(self):
        self.assertIn("block_normal_valid = false;", self.pre_solve)
        self.assertIn("contact_count == 2", self.pre_solve)
        self.assertIn("contacts[0].active && contacts[1].active", self.pre_solve)
        self.assertIn("const real_t determinant = k00 * k11 - k01 * k01;", self.pre_solve)
        self.assertIn("determinant > CMP_EPSILON", self.pre_solve)
        self.assertIn("block_inv_determinant = real_t(1.0) / determinant;", self.pre_solve)
        self.assertIn("block_normal_valid = true;", self.pre_solve)
        self.assertLess(self.pre_solve.index("block_normal_valid = false;"),
                        self.pre_solve.index("if (oneway_disabled)"))
        # The matrix must be computed after contact anchors are updated.
        self.assertLess(self.pre_solve.index("c.rA = global_A - A->get_center_of_mass();"),
                        self.pre_solve.index("block_k00 = k00;"))

    def test_velocity_iterations_only_update_rhs(self):
        self.assertIn("if (block_normal_valid", self.solve)
        self.assertIn("block_k00 * old0 - block_k01 * old1", self.solve)
        self.assertIn("block_k01 * old0 - block_k11 * old1", self.solve)
        self.assertIn("* block_inv_determinant", self.solve)
        self.assertNotIn("const real_t determinant =", self.solve)
        self.assertIn("if (block_solved)", self.solve)
        self.assertIn("if (!valid)", self.solve)

    def test_tangent_cache_follows_rotating_normal(self):
        self.assertIn(
            "previous.acc_tangent_impulse * previous.normal.dot(contact.normal)",
            self.cpp,
        )
        self.assertIn("previous.normal.dot(contact.normal) >= real_t(0.98)",
                      self.cpp)

    def test_four_complementarity_cases(self):
        k = (2.0, 1.0, 2.0)
        for b, expected in (
            ((-1.0, -1.0), (1.0 / 3.0, 1.0 / 3.0)),
            ((1.0, -1.0), (0.0, 0.5)),
            ((-1.0, 1.0), (0.5, 0.0)),
            ((1.0, 1.0), (0.0, 0.0)),
        ):
            actual = reference_two_contact_lcp(*k, *b)
            for actual_value, expected_value in zip(actual, expected):
                self.assertAlmostEqual(actual_value, expected_value, places=10)

    def test_random_spd_complementarity(self):
        rng = random.Random(87021)
        for _ in range(500):
            k00 = rng.uniform(0.2, 20.0)
            k11 = rng.uniform(0.2, 20.0)
            k01 = rng.uniform(-0.8, 0.8) * (k00 * k11) ** 0.5
            b0 = rng.uniform(-8.0, 8.0)
            b1 = rng.uniform(-8.0, 8.0)
            x0, x1 = reference_two_contact_lcp(k00, k01, k11, b0, b1)
            w0 = k00 * x0 + k01 * x1 + b0
            w1 = k01 * x0 + k11 * x1 + b1
            self.assertGreaterEqual(x0, -1e-10)
            self.assertGreaterEqual(x1, -1e-10)
            self.assertGreaterEqual(w0, -1e-10)
            self.assertGreaterEqual(w1, -1e-10)
            self.assertAlmostEqual(x0 * w0, 0.0, places=9)
            self.assertAlmostEqual(x1 * w1, 0.0, places=9)


if __name__ == "__main__":
    unittest.main()
