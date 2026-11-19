"""Numerical and GodotPhysics3D source contracts for tetra minimum-J barrier."""

from __future__ import annotations

import math
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]

REST = ((0, 0, 0), (1, 0, 0), (0, 1, 0), (0, 0, 1))


def minus(a, b):
    return tuple(x - y for x, y in zip(a, b))


def cross(a, b):
    return (a[1]*b[2] - a[2]*b[1],
            a[2]*b[0] - a[0]*b[2],
            a[0]*b[1] - a[1]*b[0])


def dot(a, b):
    return sum(x*y for x, y in zip(a, b))


def det(points):
    a, b, c, d = points
    return dot(minus(b, a), cross(minus(c, a), minus(d, a)))


def deformation_j(points, rest=REST):
    return det(points) / det(rest)


def jacobian_gradient(points, rest=REST):
    a, b, c, d = points
    u, v, w = minus(b, a), minus(c, a), minus(d, a)
    denom = det(rest)
    gb = tuple(x / denom for x in cross(v, w))
    gc = tuple(x / denom for x in cross(w, u))
    gd = tuple(x / denom for x in cross(u, v))
    ga = tuple(-(x+y+z) for x, y, z in zip(gb, gc, gd))
    return (ga, gb, gc, gd)


def solve(points, rest, inverse_mass, minimum, alpha=0, lam=0):
    """An independent double-precision XPBD unilateral update."""
    current = deformation_j(points, rest)
    if current >= minimum and lam == 0:
        return tuple(points), lam, False
    grads = jacobian_gradient(points, rest)
    weighted = sum(m*dot(g,g) for m, g in zip(inverse_mass, grads))
    if weighted <= 0:
        return tuple(points), lam, False
    delta = -(current-minimum + alpha*lam)/(weighted+alpha)
    next_lam = max(0, lam+delta)
    delta = next_lam-lam
    if not delta:
        return tuple(points), lam, False
    next_points = tuple(tuple(x + m*delta*gi for x, gi in zip(p, g))
                        for p, m, g in zip(points, inverse_mass, grads))
    return next_points, next_lam, True


class TetraMinJacobianContracts(unittest.TestCase):
    def test_signed_ratio_rest_flat_and_inverted(self):
        self.assertAlmostEqual(deformation_j(REST), 1)
        self.assertAlmostEqual(deformation_j(REST[:3] + ((0, 0, 0),)), 0)
        self.assertAlmostEqual(deformation_j(REST[:3] + ((0, 0, -0.4),)), -0.4)

    def test_negative_rest_winding(self):
        rest = (REST[0], REST[2], REST[1], REST[3])
        self.assertLess(det(rest), 0)
        self.assertAlmostEqual(deformation_j(rest, rest), 1)
        flipped = rest[:3] + ((0, 0, -0.25),)
        self.assertAlmostEqual(deformation_j(flipped, rest), -.25)

    def test_gradient_matches_finite_difference(self):
        positions = ((.1, .2, -.2), (1.2, .3, .1),
                     (.05, 1.05, .08), (.14, .02, .61))
        expected = jacobian_gradient(positions)
        eps = 1e-6
        for i in range(4):
            for k in range(3):
                plus = list(positions)
                minus_positions = list(positions)
                p, n = list(positions[i]), list(positions[i])
                p[k] += eps
                n[k] -= eps
                plus[i] = p
                minus_positions[i] = n
                fd = (deformation_j(plus)-deformation_j(minus_positions))/(2*eps)
                self.assertAlmostEqual(fd, expected[i][k], places=8)

    def test_pinned_flat_and_inverted_recovery(self):
        for z in [0, -.2, -.8]:
            positions = REST[:3] + ((0, 0, z),)
            corrected, lam, applied = solve(positions, REST, (0, 0, 0, 1), .35)
            self.assertTrue(applied)
            self.assertEqual(corrected[:3], positions[:3])
            self.assertAlmostEqual(deformation_j(corrected), .35)
            self.assertGreater(lam, 0)

    def test_compliant_vs_hard(self):
        current = REST[:3] + ((0, 0, .1),)
        hard, lh, ah = solve(current, REST, (0, 0, 0, 1), .5)
        soft, ls, ass = solve(current, REST, (0, 0, 0, 1), .5, 1.0)
        self.assertTrue(ah and ass)
        self.assertAlmostEqual(deformation_j(hard), .5)
        self.assertAlmostEqual(deformation_j(soft), .3)
        self.assertLess(ls, lh)

    def test_unilateral_release_and_inactive_branch(self):
        current = REST[:3] + ((0, 0, 1.2),)
        unchanged, lam, active = solve(current, REST, (0, 0, 0, 1), .3)
        self.assertFalse(active)
        self.assertEqual(unchanged, current)
        corrected, lam, active = solve(current, REST, (0, 0, 0, 1), .3, lam=.01)
        self.assertTrue(active)
        self.assertEqual(lam, 0)
        self.assertGreater(deformation_j(corrected), .3)

    def test_double_translation_and_scale_invariance(self):
        distorted = REST[:3] + ((0, 0, .4),)
        original = deformation_j(distorted)
        for scale, offset in [(1e-4, (0, 0, 0)), (100, (0, 0, 0)),
                              (1, (1000, -2000, 500))]:
            def transform(seq):
                return tuple(tuple(scale*x+o for x, o in zip(p, offset)) for p in seq)
            self.assertAlmostEqual(deformation_j(transform(distorted),
                                                 transform(REST)), original)

    def test_rigid_transform_gradient_sum_zero(self):
        positions = REST[:3] + ((.2, -.1, .9),)
        grads = jacobian_gradient(positions)
        for axis in range(3):
            self.assertAlmostEqual(sum(g[axis] for g in grads), 0, places=12)
        # The determinant is rotationally invariant, so net torque is zero.
        torque = [0., 0., 0.]
        for x, g in zip(positions, grads):
            c = cross(x, g)
            torque = [t+z for t, z in zip(torque, c)]
        for axis in range(3):
            self.assertAlmostEqual(torque[axis], 0, places=12)

    def test_project_settings_and_dormant_default(self):
        server = (ROOT / "servers/physics_3d/physics_server_3d.cpp").read_text()
        space_h = (ROOT / "modules/godot_physics_3d/godot_space_3d.h").read_text()
        space_cpp = (ROOT / "modules/godot_physics_3d/godot_space_3d.cpp").read_text()
        for name in ["soft_body_tetra_min_jacobian", "soft_body_tetra_min_jacobian_compliance"]:
            key = f"physics/3d/solver/{name}"
            self.assertIn(f'"{key}"', server)
            self.assertIn(f'GLOBAL_GET("{key}")', space_cpp)
            self.assertIn(f"get_{name}()", space_h)
            self.assertIn(f"{name} = 0.0", space_h)
        self.assertIn("CLAMP(configured_min_jacobian, real_t(0.0), real_t(1.0))", space_cpp)
        self.assertIn("Math::is_finite(configured_min_j_compliance)", space_cpp)

    def test_early_cook_and_solver_per_step_wiring(self):
        soft = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.cpp").read_text()
        soft_h = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.h").read_text()
        self.assertIn('"servers/physics_fem_tetra_min_jacobian.h"', soft)
        self.assertIn("LocalVector<double> xpbd_fem_min_jacobian_lambdas;", soft_h)
        self.assertIn("get_space()->get_soft_body_tetra_min_jacobian() > 0.0", soft)
        self.assertIn("get_space()->get_soft_body_tetra_min_jacobian() <= 0.0", soft)
        self.assertIn("const bool use_min_jacobian = min_jacobian > 0.0", soft)
        self.assertIn("xpbd_fem_min_jacobian_lambdas.resize(xpbd_fem_tetrahedra.size())", soft)
        self.assertIn("xpbd_fem_min_jacobian_lambdas.reset();", soft)
        self.assertIn("physics_fem_tetra_solve_min_jacobian(a.x, b.x, c.x, d.x,", soft)
        self.assertIn("min_jacobian, min_j_alpha, xpbd_fem_min_jacobian_lambdas[t]", soft)
        self.assertLess(soft.index("xpbd_fem_min_jacobian_lambdas.resize"),
                        soft.index("for (int isolve = 0; isolve < iteration_count; ++isolve)"))

    def test_helper_unilateral_transactional_guards(self):
        helper = (ROOT / "servers/physics_fem_tetra_min_jacobian.h").read_text()
        self.assertIn("const double inv_rest_det = 1.0 / p_rest.signed_det", helper)
        self.assertIn("const double next_lambda = MAX(0.0,", helper)
        self.assertIn("const double max_component = double(std::numeric_limits<real_t>::max())", helper)
        self.assertIn("for (int attempt = 0; attempt < 12; ++attempt)", helper)
        self.assertIn("candidate_j > current_j", helper)
        self.assertLess(helper.index("if (!Math::is_finite(accepted_lambda)"),
                        helper.index("r_a = next[0];"))
        self.assertNotIn("memnew(", helper)

    def test_native_cases_registered(self):
        native = (ROOT / "tests/servers/test_physics_fem_tetra_min_jacobian.cpp").read_text()
        self.assertIn("TEST_FORCE_LINK(test_physics_fem_tetra_min_jacobian)", native)
        self.assertGreaterEqual(native.count("TEST_CASE("), 15)
        self.assertIn("Inverted element recovers orientation", native)
        self.assertIn("Fully coincident points have no recovery gradient", native)


if __name__ == "__main__":
    unittest.main()
