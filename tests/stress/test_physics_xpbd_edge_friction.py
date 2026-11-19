"""Reference math and integration contracts for opt-in XPBD edge/edge friction.

Source-contract tests do not replace a native tests=yes build or cloth stress
scenes with the actual GodotPhysics3D solver.
"""
import math
import random
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


def reference_edge_friction(slip, inv_masses, s, t, mu, lambda_n):
    """Scalar tangential contact with mass-weighted two-edge barycentrics."""
    wa, wb, wc, wd = 1.0 - s, s, 1.0 - t, t
    weights = (wa, wb, -wc, -wd)
    effective_mass = sum(m * w * w for m, w in zip(inv_masses, weights))
    if effective_mass <= 0 or mu <= 0 or lambda_n <= 0 or not slip:
        return (0.0,) * 4
    impulse = -math.copysign(min(abs(slip) / effective_mass, mu * lambda_n), slip)
    return tuple(m * w * impulse for m, w in zip(inv_masses, weights))


class EdgeSelfContactFrictionTests(unittest.TestCase):
    def test_pinned_second_edge_stops_slip(self):
        correction = reference_edge_friction(0.2, (1, 1, 0, 0), 0.5, 0.5, 1, 1)
        self.assertAlmostEqual(correction[0], -0.2)
        self.assertAlmostEqual(correction[1], -0.2)
        self.assertEqual(correction[2:], (0, 0))

    def test_coulomb_cap(self):
        correction = reference_edge_friction(0.2, (1, 1, 0, 0), 0.5, 0.5, 0.05, 0.5)
        self.assertAlmostEqual(correction[0], -0.0125)
        self.assertAlmostEqual(correction[1], -0.0125)

    def test_default_and_zero_normal_reaction(self):
        for mu, normal in ((0, 1), (1, 0), (0, 0)):
            self.assertEqual(reference_edge_friction(0.2, (1, 1, 1, 1), 0.5, 0.5, mu, normal),
                             (0, 0, 0, 0))

    def test_randomized_momentum_and_nonincreasing_slip(self):
        rng = random.Random(20261119)
        for _ in range(5000):
            masses = tuple(0 if rng.random() < 0.15 else 10 ** rng.uniform(-2, 2)
                           for _ in range(4))
            s = rng.uniform(0.01, 0.99)
            t = rng.uniform(0.01, 0.99)
            slip = rng.uniform(-5, 5)
            mu = rng.uniform(0, 2)
            normal = rng.uniform(0, 4)
            correction = reference_edge_friction(slip, masses, s, t, mu, normal)
            weights = (1.0 - s, s, -(1.0 - t), -t)
            relative = sum(delta * w for delta, w in zip(correction, weights))
            self.assertLessEqual(abs(slip + relative), abs(slip) + 1e-10)
            if all(m > 0 for m in masses):
                self.assertAlmostEqual(sum(d / m for d, m in zip(correction, masses)),
                                       0.0, delta=1e-9)
            impulse = (correction[0] / (masses[0] * weights[0])
                       if masses[0] and weights[0] else 0.0)
            self.assertLessEqual(abs(impulse), mu * normal + 1e-9)

    def test_kernel_guards_and_transactional_commit(self):
        src = (ROOT / "servers/physics_xpbd_edge_friction.h").read_text()
        self.assertIn("physics_xpbd_closest_edges(", src)
        self.assertIn("const double weighted_mass", src)
        self.assertIn("const double max_impulse", src)
        self.assertIn("p_normal_lambda > real_t(0.0)", src)
        self.assertIn("p_prev_a.is_finite()", src)
        self.assertIn("!next_a.is_finite() || !next_b.is_finite()", src)
        self.assertLess(src.index("if (!next_a.is_finite()"), src.index("r_a = next_a;"))

    def test_opt_in_pipeline_and_native_regression_registration(self):
        src = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.cpp").read_text()
        block = src.split("bool GodotSoftBody3D::solve_edge_self_collisions(", 1)[1]
        block = block.split("void GodotSoftBody3D::solve_self_collisions(", 1)[0]
        self.assertIn('#include "servers/physics_xpbd_edge_friction.h"', src)
        self.assertLess(block.index("physics_xpbd_solve_edge_collision("),
                        block.index("physics_xpbd_solve_edge_friction("))
        self.assertIn("if (friction > real_t(0.0))", block)
        self.assertIn("friction, contact.lambda, thickness, contact.normal", block)
        self.assertIn("a.q, b.q, c.q, d.q", block)
        self.assertLess(block.index("physics_xpbd_solve_edge_friction("), block.index("return true;"))
        native = (ROOT / "tests/servers/test_physics_xpbd_edge_friction.cpp").read_text()
        self.assertEqual(native.count('TEST_CASE("[PhysicsEdgeFriction]'), 8)

    def test_existing_setting_stays_disabled_by_default(self):
        src = (ROOT / "modules/godot_physics_3d/godot_space_3d.h").read_text()
        self.assertIn("soft_body_self_collision_friction = 0.0;", src)


if __name__ == "__main__":
    unittest.main()
