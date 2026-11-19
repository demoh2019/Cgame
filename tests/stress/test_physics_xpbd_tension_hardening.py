"""Numerical and source-wiring contracts for nonlinear XPBD tensile links."""

import math
import pathlib
import random
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


def alpha_for_step(length, rest, base, yield_strain, hardening):
    if rest <= 0 or hardening <= 0 or base <= 0:
        return base
    excess = (length - rest) / rest - yield_strain
    if excess <= 0:
        return base
    return base / (1.0 + min(1e6, hardening * excess * excess))


def solve_fixed_alpha(length, rest, inv_a, inv_b, alpha, iterations):
    inv_sum = inv_a + inv_b
    lam = 0.0
    for _ in range(iterations):
        dl = (rest - length - alpha * lam) / (inv_sum + alpha)
        length += inv_sum * dl
        lam += dl
    return length, lam


class TestTensionHardening(unittest.TestCase):
    def test_frozen_alpha_preserves_convergence(self):
        rng = random.Random(0x518E)
        for _ in range(3000):
            length = rng.uniform(0.05, 30.0)
            rest = rng.uniform(0.1, 4.0)
            base = 10 ** rng.uniform(-4.0, 2.0)
            hardening = 10 ** rng.uniform(-2.0, 4.0)
            yield_strain = rng.uniform(0.0, 0.8)
            a = rng.uniform(0.01, 2)
            b = rng.uniform(0.01, 2)
            alpha = alpha_for_step(length, rest, base, yield_strain, hardening)
            result, lam = solve_fixed_alpha(length, rest, a, b, alpha, 32)
            exact = (alpha * length + (a + b) * rest) / (a + b + alpha)
            self.assertAlmostEqual(result, exact, delta=1e-9 * (1 + abs(exact)))
            self.assertTrue(math.isfinite(lam))
            self.assertLessEqual(alpha, base)
            self.assertGreaterEqual(alpha, base / (1 + 1e6))

    def test_compression_is_unaffected(self):
        self.assertEqual(alpha_for_step(0.3, 1, 0.6, 0.1, 1000), 0.6)
        self.assertEqual(alpha_for_step(1.05, 1, 0.6, 0.1, 1000), 0.6)
        self.assertLess(alpha_for_step(2.0, 1, 0.6, 0.1, 1000), 0.6)

    def test_freezing_avoids_iteration_oscillation(self):
        length = 3.0
        fixed_alpha = alpha_for_step(length, 1, 1, 0, 100)
        frozen, _ = solve_fixed_alpha(length, 1, 1, 1, fixed_alpha, 32)
        self.assertLess(frozen - 1, 0.01)
        dynamic_length, lam = length, 0.0
        for _ in range(32):
            a = alpha_for_step(dynamic_length, 1, 1, 0, 100)
            dl = (1 - dynamic_length - a * lam) / (2 + a)
            dynamic_length += 2 * dl
            lam += dl
        self.assertGreater(dynamic_length - frozen, 0.5)

    def test_source_wiring_default_and_cache_scope(self):
        server = (ROOT / "servers/physics_3d/physics_server_3d.cpp").read_text()
        space_h = (ROOT / "modules/godot_physics_3d/godot_space_3d.h").read_text()
        space_cpp = (ROOT / "modules/godot_physics_3d/godot_space_3d.cpp").read_text()
        body_h = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.h").read_text()
        body_cpp = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.cpp").read_text()
        solver_h = (ROOT / "servers/physics_xpbd_tension_hardening.h").read_text()
        self.assertIn('"physics/3d/solver/soft_body_xpbd_tension_hardening"', server)
        self.assertIn('"physics/3d/solver/soft_body_xpbd_tension_yield_strain"', server)
        self.assertIn("real_t soft_body_xpbd_tension_hardening = 0.0;", space_h)
        self.assertIn('GLOBAL_GET("physics/3d/solver/soft_body_xpbd_tension_hardening")', space_cpp)
        self.assertIn("LocalVector<real_t> xpbd_link_hardening_alphas;", body_h)
        self.assertIn("const bool use_tension_hardening = use_xpbd &&", body_cpp)
        self.assertIn("if (use_tension_hardening || use_compression_hardening) {\n\t\txpbd_link_hardening_alphas.resize", body_cpp)
        self.assertIn("xpbd_link_hardening_alphas.reset();", body_cpp)
        self.assertIn("(use_tension_hardening || use_compression_hardening) ? xpbd_link_hardening_alphas[link_index] : alpha", body_cpp)
        self.assertIn("physics_xpbd_tension_hardening_alpha(", solver_h)
        self.assertLess(body_cpp.index("physics_xpbd_tension_hardening_alpha("),
                        body_cpp.index("for (int isolve = 0; isolve < iteration_count; ++isolve)"))


if __name__ == "__main__":
    unittest.main()
