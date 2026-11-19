"""XPBD soft-body vertex/face friction numerical and source integration tests.

Run from repository root:
 python3 -m unittest discover -s tests/stress -p test_physics_xpbd_self_friction.py -v
These do not replace native C++ doctests or scene-level stress testing.
"""
import math
import random
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


def reference_tangent_impulse(displacement, weights, mu, lambda_n):
    """Independent 1D tangential sliding reference with barycentric face weights."""
    inv_vertex, inv_a, inv_b, inv_c = weights
    # Contact barycentrics for x=0.45, y=0.25 on the unit right triangle.
    bary = (0.30, 0.45, 0.25)
    m = inv_vertex + sum(w * p * p for w, p in zip(weights[1:], bary))
    if m <= 0 or mu <= 0 or lambda_n <= 0:
        return (0.0, 0.0, 0.0, 0.0)
    impulse = -math.copysign(min(abs(displacement) / m, mu * lambda_n), displacement)
    return (inv_vertex * impulse,) + tuple(-w * p * impulse for w, p in zip(weights[1:], bary))


class XPBDSelfContactFrictionTests(unittest.TestCase):
    def test_fixed_face_stops_slide_with_sufficient_normal_reaction(self):
        corrections = reference_tangent_impulse(0.2, (1, 0, 0, 0), 1, 0.5)
        self.assertAlmostEqual(corrections[0], -0.2)
        self.assertEqual(corrections[1:], (0, 0, 0))

    def test_coulomb_limit(self):
        corrections = reference_tangent_impulse(0.2, (1, 0, 0, 0), 0.05, 0.5)
        self.assertAlmostEqual(corrections[0], -0.025)

    def test_no_reaction_and_zero_friction(self):
        for mu, normal_lambda in ((0, 0.5), (1, 0), (0, 0)):
            self.assertEqual(reference_tangent_impulse(0.2, (1, 1, 1, 1), mu, normal_lambda), (0, 0, 0, 0))

    def test_pinned_vertex_and_moveable_face(self):
        d = reference_tangent_impulse(-0.2, (0, 1, 1, 1), 1, 0.5)
        self.assertEqual(d[0], 0)
        self.assertLess(d[1], 0)
        self.assertLess(d[2], 0)
        self.assertLess(d[3], 0)

    def test_randomized_momentum_and_friction_budget(self):
        rng = random.Random(20261119)
        for _ in range(5000):
            masses = tuple((0 if rng.random() < 0.2 else 10 ** rng.uniform(-2, 2)) for _ in range(4))
            m0 = masses[0] + 0.3 ** 2 * masses[1] + 0.45 ** 2 * masses[2] + 0.25 ** 2 * masses[3]
            if m0 == 0:
                continue
            displacement = rng.uniform(-8, 8)
            mu, normal_lambda = rng.uniform(0, 2), rng.uniform(0, 3)
            corrections = reference_tangent_impulse(displacement, masses, mu, normal_lambda)
            # Equal-and-opposite impulse, weighted by barycentric face influences.
            momentum = sum(delta / w for delta, w in zip(corrections, masses) if w > 0)
            # Face impulses must be barycentrically weighted, so conserve total.
            self.assertAlmostEqual(momentum, 0.0, places=10)
            self.assertLessEqual(abs(corrections[0]) / masses[0] if masses[0] else 0.0,
                                 mu * normal_lambda + 1e-9)
            # Relative normal-plane displacement after friction is reduced.
            relative = corrections[0] - (
                0.30 * corrections[1] + 0.45 * corrections[2] + 0.25 * corrections[3]
            )
            self.assertLessEqual(abs(displacement + relative), abs(displacement) + 1e-9)

    def test_settings_cached_default_off(self):
        server = (ROOT / "servers/physics_3d/physics_server_3d.cpp").read_text()
        space_h = (ROOT / "modules/godot_physics_3d/godot_space_3d.h").read_text()
        space_cpp = (ROOT / "modules/godot_physics_3d/godot_space_3d.cpp").read_text()
        self.assertIn('"physics/3d/solver/soft_body_self_collision_friction"', server)
        self.assertIn('"), 0.0);', server)
        self.assertIn("soft_body_self_collision_friction = 0.0;", space_h)
        self.assertIn("get_soft_body_self_collision_friction()", space_h)
        self.assertIn("Math::is_finite(configured_self_friction)", space_cpp)

    def test_friction_follows_normal_projection_before_velocity_reconstruction(self):
        src = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.cpp").read_text()
        begin = src.index("void GodotSoftBody3D::solve_self_collisions(")
        end = src.index("void GodotSoftBody3D::update_area()", begin)
        code = src[begin:end]
        self.assertIn("if (friction > real_t(0.0))", code)
        self.assertLess(code.index("physics_xpbd_solve_self_collision("),
                        code.index("physics_xpbd_solve_self_friction("))
        self.assertLess(code.index("physics_xpbd_solve_self_friction("),
                        code.index("update_face_tree(real_t(0.0));", code.index("physics_xpbd_solve_self_friction(")))
        self.assertIn("vertex.q, face.n[0]->q, face.n[1]->q, face.n[2]->q,", code)
        self.assertIn("contact.lambda, thickness", code)

    def test_kernel_uses_double_and_transactional_update(self):
        src = (ROOT / "servers/physics_xpbd_self_friction.h").read_text()
        self.assertIn("const double weighted_mass", src)
        self.assertIn("const double max_impulse", src)
        self.assertIn("const Vector3 next_vertex(", src)
        self.assertIn("if (!next_vertex.is_finite() || !next_a.is_finite()", src)
        self.assertLess(src.index("if (!next_vertex.is_finite()"),
                        src.index("r_vertex = next_vertex;"))
        self.assertIn("physics_xpbd_self_collision_face_projection(", src)
        self.assertIn("p_normal_lambda > real_t(0.0)", src)
        native = (ROOT / "tests/servers/test_physics_xpbd_self_friction.cpp").read_text()
        self.assertEqual(native.count('TEST_CASE("[PhysicsSelfFriction]'), 8)


if __name__ == "__main__":
    unittest.main()
