"""Reference numerical/source-contract checks for irreversible XPBD soft-body fatigue.

The native C++ tests exercise the kernel. This independent Python reference
checks monotonic damage, time-step invariance and opt-in source wiring.
"""

import math
from pathlib import Path
import random
import unittest

ROOT = Path(__file__).resolve().parents[2]


def accumulate_damage(old, length, rest, yield_strain, rate, cap, dt):
    if rate <= 0 or dt <= 0 or old >= cap:
        return old
    excess = max(0.0, abs(length / rest - 1.0) - yield_strain)
    if excess == 0:
        return old
    exponent = rate * excess * dt
    remaining = 0.0 if exponent >= 50 else math.exp(-exponent)
    return min(cap, max(old, cap - (cap - old) * remaining))


def compliance_alpha(alpha, damage):
    return alpha / (1.0 - damage)


class TestSoftBodyFatigueDamage(unittest.TestCase):
    def test_zero_rate_is_backward_compatible(self):
        rng = random.Random(0xC0FE)
        for _ in range(1000):
            old = rng.uniform(0, 0.8)
            self.assertEqual(accumulate_damage(old, rng.uniform(0.01, 3),
                                               1, 0.2, 0, 0.9, 0.01), old)
        self.assertEqual(compliance_alpha(0.1, 0), 0.1)

    def test_yield_threshold_is_not_damaging(self):
        self.assertEqual(accumulate_damage(0.15, 1.19, 1, 0.2, 100, 0.9, 1), 0.15)
        self.assertEqual(accumulate_damage(0.15, 0.81, 1, 0.2, 100, 0.9, 1), 0.15)
        self.assertGreater(accumulate_damage(0.15, 1.25, 1, 0.2, 5, 0.9, 1), 0.15)

    def test_accumulation_remains_bounded_and_irreversible(self):
        rng = random.Random(0xDA6E)
        for _ in range(3000):
            cap = rng.uniform(0.05, 0.99)
            old = rng.uniform(0, cap)
            stretch = rng.uniform(0.01, 5.0)
            rate = 10 ** rng.uniform(-3, 3)
            dt = rng.uniform(0.0001, 1)
            new = accumulate_damage(old, stretch, 1, 0.1, rate, cap, dt)
            self.assertGreaterEqual(new, old)
            self.assertLessEqual(new, cap)
            self.assertTrue(math.isfinite(new))
            self.assertGreaterEqual(compliance_alpha(1, new), 1)

    def test_two_half_steps_equal_one_whole_step(self):
        rng = random.Random(0x51F7)
        for _ in range(3000):
            cap = 0.95
            d = rng.uniform(0, cap)
            rest = rng.uniform(0.2, 20.0)
            length = rest * rng.uniform(0.01, 3)
            rate = rng.uniform(0.001, 10)
            duration = rng.uniform(0.001, 2)
            once = accumulate_damage(d, length, rest, 0.15, rate, cap, duration)
            twice = accumulate_damage(
                accumulate_damage(d, length, rest, 0.15, rate, cap, duration / 2),
                length, rest, 0.15, rate, cap, duration / 2
            )
            self.assertAlmostEqual(once, twice, delta=2e-12)

    def test_material_weakens_constraint_without_changing_pins(self):
        def solve(alpha, initial=2.0, rest=1.0):
            pos, lagrange = initial, 0.0
            for _ in range(20):
                dl = (rest - pos - alpha * lagrange) / (1 + alpha)
                pos += dl
                lagrange += dl
            return pos
        pristine = solve(compliance_alpha(1, 0))
        damaged = solve(compliance_alpha(1, 0.8))
        self.assertGreater(damaged, pristine)
        self.assertLess(damaged, 2.0)
        self.assertGreater(pristine, 1.0)

    def test_damage_matches_compression_and_tension_magnitude(self):
        self.assertAlmostEqual(
            accumulate_damage(0, 1.4, 1, 0.1, 5, 0.9, 0.1),
            accumulate_damage(0, 0.6, 1, 0.1, 5, 0.9, 0.1),
        )

    def test_wiring_and_topology_reset(self):
        server = (ROOT / "servers/physics_3d/physics_server_3d.cpp").read_text()
        space_h = (ROOT / "modules/godot_physics_3d/godot_space_3d.h").read_text()
        space_cpp = (ROOT / "modules/godot_physics_3d/godot_space_3d.cpp").read_text()
        body_h = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.h").read_text()
        body_cpp = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.cpp").read_text()
        header = (ROOT / "servers/physics_softbody_fatigue_damage.h").read_text()
        for name in ("damage_rate", "yield_strain", "max_damage"):
            name = "soft_body_fatigue_" + name
            self.assertIn("physics/3d/solver/" + name, server)
            self.assertIn('GLOBAL_GET("physics/3d/solver/' + name + '")', space_cpp)
            self.assertIn(name, space_h)
        self.assertIn('real_t soft_body_fatigue_damage_rate = 0.0;', space_h)
        self.assertIn('LocalVector<real_t> xpbd_link_fatigue_damage;', body_h)
        self.assertIn('if (use_fatigue)', body_cpp)
        self.assertIn('physics_softbody_accumulate_fatigue_damage(', body_cpp)
        self.assertIn('physics_softbody_fatigue_compliance_alpha(', body_cpp)
        self.assertIn('xpbd_link_fatigue_damage.reset();', body_cpp)
        self.assertIn('physics_softbody_accumulate_fatigue_damage(', header)
        begin = body_cpp.index("void GodotSoftBody3D::solve_constraints(")
        accumulate = body_cpp.index("physics_softbody_accumulate_fatigue_damage(", begin)
        solver = body_cpp.index("for (int isolve = 0; isolve < iteration_count; ++isolve)", begin)
        self.assertLess(accumulate, solver)
        destroy = body_cpp.index("void GodotSoftBody3D::destroy()")
        self.assertIn('xpbd_link_fatigue_damage.reset();', body_cpp[destroy:])


if __name__ == "__main__":
    unittest.main()
