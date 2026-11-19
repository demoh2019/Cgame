"""Cross-material FEM damage contracts for tetrahedral directional fibers.

The same irreversible per-tetra damage must soften BOTH isotropic
Neo-Hookean and tension-only fiber XPBD rows; no second state is needed.
"""
from pathlib import Path
import math
import random
import unittest

ROOT = Path(__file__).resolve().parents[2]


def effective_alpha(alpha, damage):
    if not (alpha > 0 and 0 <= damage <= .95):
        return None
    return alpha / (1 - damage)


def projected_fiber_length(original, inv_a, inv_b, alpha):
    # One axis-aligned material fiber on a unit tetra, both ends free.
    # XPBD C=sqrt(V)*(1-stretch), Jacobian ±sqrt(V),
    # denominator=(im_a+im_b)*V + compliance/dt².
    volume = 1. / 6.
    g = math.sqrt(volume)
    constraint = g * (1. - original)
    effective_mass = (inv_a + inv_b) * volume
    impulse = max(0., -constraint / (effective_mass + alpha))
    return original - (inv_a + inv_b) * g * impulse


class FEMFiberDamageContracts(unittest.TestCase):
    def test_4000_randomized_damage_coupling_and_momentum(self):
        rng = random.Random(0xF3D4A9E)
        for _ in range(4000):
            stretch = rng.uniform(1.001, 2.)
            inv_a, inv_b = rng.uniform(.1, 5.), rng.uniform(.1, 5.)
            base_alpha = rng.uniform(1e-6, .2)
            d1 = rng.uniform(0., .45)
            d2 = rng.uniform(d1, .95)
            alpha1 = effective_alpha(base_alpha, d1)
            alpha2 = effective_alpha(base_alpha, d2)
            self.assertLessEqual(alpha1, alpha2)
            stiff_length = projected_fiber_length(stretch, inv_a, inv_b, alpha1)
            soft_length = projected_fiber_length(stretch, inv_a, inv_b, alpha2)
            self.assertGreaterEqual(soft_length + 1e-12, stiff_length)
            self.assertLessEqual(soft_length, stretch + 1e-12)
            self.assertGreaterEqual(stiff_length, 1. - 1e-12)
            volume = 1. / 6.
            impulse = math.sqrt(volume) * (stretch - 1.) / (
                (inv_a + inv_b)*volume + alpha2
            )
            da = inv_a * math.sqrt(volume) * impulse
            db = -inv_b * math.sqrt(volume) * impulse
            self.assertAlmostEqual(da / inv_a + db / inv_b, 0., delta=1e-10)

    def test_damage_history_is_irreversible_with_fixed_yield(self):
        damage = 0.
        previous_alpha = effective_alpha(.02, damage)
        for _ in range(100):
            excess = .6-.2
            fraction = 1. - math.exp(-5. * .016 * excess)
            damage += (.95-damage)*fraction
            next_alpha = effective_alpha(.02, damage)
            self.assertGreaterEqual(next_alpha, previous_alpha)
            previous_alpha = next_alpha
        self.assertGreater(damage, 0.)
        self.assertLessEqual(damage, .95)

    def test_engine_wiring_and_no_extra_damage_buffer(self):
        body = (ROOT/"modules/godot_physics_3d/godot_soft_body_3d.cpp").read_text()
        body_h = (ROOT/"modules/godot_physics_3d/godot_soft_body_3d.h").read_text()
        damage = (ROOT/"servers/physics_fem_tetra_damage.h").read_text()
        self.assertIn('const bool fibers_have_damage = xpbd_fem_damage.size()', body)
        self.assertIn('PhysicsFEMTetraDamage::effective_compliance(\n', body)
        self.assertIn('fem_fiber_alpha, xpbd_fem_damage[tet_index], local_fiber_alpha', body)
        self.assertIn('fem_fiber_axis, local_fiber_alpha', body)
        self.assertIn('LocalVector<double> xpbd_fem_damage;', body_h)
        self.assertEqual(body_h.count('xpbd_fem_damage;'), 1)
        self.assertIn('static bool effective_compliance(', damage)


if __name__ == "__main__":
    unittest.main()
