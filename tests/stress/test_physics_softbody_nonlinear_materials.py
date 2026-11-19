"""Numerical and source-wiring regression contracts for nonlinear soft-body materials.

Run:
  python3 -m unittest discover -s tests/stress -p test_physics_softbody_nonlinear_materials.py -v

The Python reference checks physical invariants independently of the C++ code;
native doctests in tests/servers cover the actual Godot C++ helper functions.
"""

import math
from pathlib import Path
import random
import unittest

ROOT = Path(__file__).resolve().parents[2]


def compression_alpha(length, rest, alpha, yield_strain, hardening):
    if rest <= 0 or alpha <= 0 or hardening <= 0:
        return alpha
    excess = (rest - length) / rest - yield_strain
    if excess <= 0:
        return alpha
    return alpha / (1 + min(1e6, hardening * excess * excess))


def tension_alpha(length, rest, alpha, yield_strain, hardening):
    if rest <= 0 or alpha <= 0 or hardening <= 0:
        return alpha
    excess = (length - rest) / rest - yield_strain
    if excess <= 0:
        return alpha
    return alpha / (1 + min(1e6, hardening * excess * excess))


def damp_1d(velocity_a, velocity_b, inv_a, inv_b, rest,
            strength, yield_rate, dt):
    relative = velocity_b - velocity_a
    rate = abs(relative) / rest
    excess = max(0.0, rate - yield_rate)
    if strength <= 0 or excess <= 0 or dt <= 0:
        return velocity_a, velocity_b
    fraction = -math.expm1(-strength * dt * excess)
    impulse = -fraction * relative / (inv_a + inv_b)
    return velocity_a - inv_a * impulse, velocity_b + inv_b * impulse


class TestSoftbodyNonlinearMaterials(unittest.TestCase):
    def test_compression_stiffens_only_past_yield(self):
        self.assertEqual(compression_alpha(1.01, 1, 1, 0, 100), 1)
        self.assertEqual(compression_alpha(0.9, 1, 1, 0.2, 100), 1)
        self.assertAlmostEqual(compression_alpha(0.5, 1, 1, 0.2, 100), 0.1)
        self.assertLess(compression_alpha(0.1, 1, 1, 0, 100),
                        compression_alpha(0.6, 1, 1, 0, 100))

    def test_tension_and_compression_are_independent(self):
        rng = random.Random(0xC04E)
        for _ in range(2000):
            rest = rng.uniform(0.01, 20.0)
            current = rest * rng.uniform(0.01, 3.0)
            base = 10 ** rng.uniform(-5, 3)
            one = tension_alpha(current, rest, base, 0.12, 90)
            combined = compression_alpha(current, rest, one, 0.08, 120)
            if current >= rest:
                self.assertEqual(combined, one)
            else:
                self.assertEqual(one, base)
                self.assertLessEqual(combined, base)
            self.assertTrue(math.isfinite(combined))
            self.assertGreaterEqual(combined, 0)

    def test_fixed_step_compliance_converges_without_iteration_dependency(self):
        for length in [0.03, 0.15, 0.35, 0.6, 0.95]:
            rest = 1.0
            base = 2.0
            wa, wb = 1.0, 0.0
            alpha = compression_alpha(length, rest, base, 0, 50)
            distance, lam = length, 0.0
            for _ in range(30):
                dl = (rest - distance - alpha * lam) / (wa + wb + alpha)
                distance += (wa + wb) * dl
                lam += dl
            expected = (alpha * length + (wa + wb) * rest) / (wa + wb + alpha)
            self.assertAlmostEqual(distance, expected, delta=1e-12)
            self.assertGreaterEqual(distance, length)

    def test_viscosity_ignores_slow_motion_and_tangential_direction(self):
        self.assertEqual(damp_1d(1, 2, 1, 1, 1, 2, 3, 1), (1, 2))
        self.assertEqual(damp_1d(1, 8, 1, 1, 1, 0, 0, 1), (1, 8))
        self.assertEqual(damp_1d(1, 8, 1, 1, 1, 2, 0, 0), (1, 8))

    def test_viscosity_random_mass_weighted_momentum_and_energy(self):
        rng = random.Random(0xFEED)
        for _ in range(4000):
            wa = 10 ** rng.uniform(-2, 1) if rng.randrange(5) else 0
            wb = 10 ** rng.uniform(-2, 1) if rng.randrange(5) else 0
            if wa + wb == 0:
                continue
            va, vb = rng.uniform(-30, 30), rng.uniform(-30, 30)
            rest = 10 ** rng.uniform(-1, 1)
            rate = rng.uniform(0, 5)
            strength = rng.uniform(0, 30)
            dt = rng.uniform(0.001, 0.1)
            after_a, after_b = damp_1d(va, vb, wa, wb, rest, strength, rate, dt)
            if wa and wb:
                before_p = va / wa + vb / wb
                after_p = after_a / wa + after_b / wb
                self.assertAlmostEqual(after_p, before_p, delta=1e-8 * (1 + abs(before_p)))
            elif wa == 0:
                self.assertEqual(after_a, va)
            else:
                self.assertEqual(after_b, vb)
            self.assertLessEqual(abs(after_b - after_a), abs(vb - va) + 1e-10)
            if wa and wb:
                initial_energy = va * va / wa + vb * vb / wb
                final_energy = after_a * after_a / wa + after_b * after_b / wb
                self.assertLessEqual(final_energy, initial_energy + 1e-9)

    def test_strain_rate_increases_damping_for_fast_impacts(self):
        def lost_fraction(speed):
            a, b = damp_1d(0, speed, 1, 1, 1, 0.5, 0.1, 0.05)
            return 1 - (b - a) / speed
        self.assertLess(lost_fraction(1), lost_fraction(10))
        self.assertLess(lost_fraction(10), lost_fraction(100))

    def test_source_wiring_default_disabled(self):
        server = (ROOT / "servers/physics_3d/physics_server_3d.cpp").read_text()
        space_h = (ROOT / "modules/godot_physics_3d/godot_space_3d.h").read_text()
        space_cpp = (ROOT / "modules/godot_physics_3d/godot_space_3d.cpp").read_text()
        soft = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.cpp").read_text()
        defaults = {
            "soft_body_xpbd_compression_hardening": "0.0",
            "soft_body_xpbd_compression_yield_strain": "0.1",
            "soft_body_strain_rate_damping": "0.0",
            "soft_body_strain_rate_yield": "0.0",
        }
        for prop, default in defaults.items():
            self.assertIn(f'"physics/3d/solver/{prop}"', server)
            self.assertIn(f'{prop} = {default};', space_h)
            self.assertIn(f'GLOBAL_GET("physics/3d/solver/{prop}")', space_cpp)
        self.assertIn("get_soft_body_strain_rate_damping()", soft)
        self.assertIn("get_soft_body_xpbd_compression_hardening()", soft)
        self.assertIn("physics_xpbd_compression_hardening_alpha(", soft)
        self.assertIn("physics_softbody_damp_strain_rate(", soft)
        self.assertIn("use_tension_hardening || use_compression_hardening || use_anisotropic_stretch", soft)
        self.assertIn("if (strain_rate_damping > real_t(0.0)", soft)
        begin = soft.index("void GodotSoftBody3D::solve_constraints(")
        damp = soft.index("physics_softbody_damp_strain_rate(", begin)
        prediction = soft.index("node.x = node.q + node.v * p_delta;", begin)
        hardening = soft.index("physics_xpbd_compression_hardening_alpha(", begin)
        solver = soft.index("for (int isolve = 0; isolve < iteration_count; ++isolve)", begin)
        self.assertLess(damp, prediction)
        self.assertLess(hardening, solver)


if __name__ == "__main__":
    unittest.main()
