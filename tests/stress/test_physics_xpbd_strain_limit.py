"""Reference math and source integration contracts for XPBD soft-body strain limits.

Run: python3 -m unittest discover -s tests/stress -p test_physics_xpbd_strain_limit.py -v
Native counterpart: tests/servers/test_physics_xpbd_strain_limit.cpp

This independently validates the two unilateral XPBD constraints. Passing
this Python suite is NOT a substitute for compiling or running native tests.
"""

import math
import random
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


def project(a, b, inv_a, inv_b, rest, min_ratio, max_ratio, alpha, lambdas=(0.0, 0.0)):
    """Reference XPBD projection with nonpositive stretch/compression multipliers."""
    if not all(math.isfinite(x) for x in (
            *a, *b, inv_a, inv_b, rest, min_ratio, max_ratio, alpha, *lambdas)):
        return None
    if (inv_a < 0 or inv_b < 0 or inv_a + inv_b <= 0 or rest <= 0 or
            min_ratio < 0 or min_ratio > 1 or max_ratio < 0 or
            (max_ratio > 0 and max_ratio < 1) or
            (max_ratio > 0 and min_ratio > max_ratio) or
            (min_ratio == 0 and max_ratio == 0) or alpha < 0 or
            any(lmb > 0 for lmb in lambdas)):
        return None
    a, b = list(a), list(b)
    stretch, compression = lambdas
    dnom = inv_a + inv_b + alpha
    changed = False
    for upper, ratio in ((True, max_ratio), (False, min_ratio)):
        if ratio == 0:
            continue
        d = [b[i] - a[i] for i in range(3)]
        length = math.sqrt(sum(v * v for v in d))
        if not math.isfinite(length) or length <= 0:
            return None
        c = length - rest * ratio if upper else rest * ratio - length
        lam = stretch if upper else compression
        if c <= 0 and lam == 0:
            continue
        next_lam = min(0.0, lam - (c + alpha * lam) / dnom)
        dl = next_lam - lam
        if dl == 0:
            continue
        signed = (1 if upper else -1) * dl / length
        next_a = [a[i] - inv_a * signed * d[i] for i in range(3)]
        next_b = [b[i] + inv_b * signed * d[i] for i in range(3)]
        if not all(math.isfinite(v) for v in next_a + next_b):
            return None
        a, b = next_a, next_b
        if upper:
            stretch = next_lam
        else:
            compression = next_lam
        changed = True
    return (a, b, (stretch, compression)) if changed else None


class XPBDStrainLimitContracts(unittest.TestCase):
    def test_stretch_clamps_without_moving_center_of_mass(self):
        out = project((0, 0, 0), (2, 0, 0), 1, 1, 1, 0, 1.25, 0)
        self.assertIsNotNone(out)
        self.assertAlmostEqual(out[0][0], 0.375)
        self.assertAlmostEqual(out[1][0], 1.625)
        self.assertAlmostEqual(out[2][0], -0.375)

    def test_compression_and_pinned_nodes(self):
        out = project((0, 0, 0), (.2, 0, 0), 0, 1, 1, .5, 0, 0)
        self.assertIsNotNone(out)
        self.assertEqual(out[0], [0, 0, 0])
        self.assertAlmostEqual(out[1][0], .5)
        self.assertAlmostEqual(out[2][1], -.3)

    def test_compliant_xpbd_is_iteration_invariant(self):
        start = ((0, 0, 0), (2, 0, 0))
        first = project(*start, 1, 1, 1, 0, 1.25, .5)
        self.assertIsNotNone(first)
        current = first
        for _ in range(32):
            attempt = project(*current[:2], 1, 1, 1, 0, 1.25, .5, current[2])
            if attempt is not None:
                current = attempt
        self.assertAlmostEqual(current[1][0] - current[0][0], 1.4)
        self.assertAlmostEqual(current[2][0], -.3)

    def test_bound_can_release_when_link_is_slack(self):
        active = project((0, 0, 0), (2, 0, 0), 1, 1, 1, 0, 1.25, 0)
        self.assertIsNotNone(active)
        a, _, lmb = active
        b = (a[0] + 0.1, 0, 0)
        released = project(a, b, 1, 1, 1, 0, 1.25, 0, lmb)
        self.assertIsNotNone(released)
        self.assertEqual(released[2][0], 0.0)
        self.assertLessEqual(released[1][0] - released[0][0], 1.25)

    def test_random_scales_and_hard_constraints(self):
        rng = random.Random(20261119)
        for _ in range(6000):
            scale = 10 ** rng.uniform(-16, 25)
            length = scale * rng.uniform(0.025, 3)
            a = (0.0, 0.0, 0.0)
            b = (length, 0.0, 0.0)
            inv_a = 0.0 if rng.random() < .25 else rng.uniform(.1, 3)
            inv_b = 0.0 if rng.random() < .25 else rng.uniform(.1, 3)
            if not (inv_a + inv_b):
                continue
            lower = rng.choice((0, .25, .5, .75, 1))
            upper = rng.choice((0, 1, 1.25, 1.75, 2))
            if not (lower or upper):
                continue
            outcome = project(a, b, inv_a, inv_b, scale, lower, upper, 0)
            if outcome is None:
                self.assertGreaterEqual(length, scale * lower - 1e-15 * scale)
                if upper:
                    self.assertLessEqual(length, scale * upper + 1e-15 * scale)
                continue
            new_a, new_b, lambdas = outcome
            self.assertTrue(all(math.isfinite(v) for v in (*new_a, *new_b, *lambdas)))
            self.assertLessEqual(lambdas[0], 0.0)
            self.assertLessEqual(lambdas[1], 0.0)
            if inv_a == 0:
                self.assertEqual(new_a, list(a))
            if inv_b == 0:
                self.assertEqual(new_b, list(b))
            corrected = math.dist(new_a, new_b)
            self.assertGreaterEqual(corrected, scale * lower - 1e-7 * scale)
            if upper:
                self.assertLessEqual(corrected, scale * upper + 1e-7 * scale)

    def test_invalid_geometry_is_atomic(self):
        self.assertIsNone(project((0, 0, 0), (0, 0, 0), 1, 1, 1, .5, 0, 0))
        self.assertIsNone(project((0, 0, 0), (2, 0, 0), 1, 1, 1, 1.2, 0, 0))
        self.assertIsNone(project((0, 0, 0), (2, 0, 0), -1, 1, 1, 0, 1.25, 0))
        self.assertIsNone(project((0, 0, 0), (2, 0, 0), 1, 1, 1, 0, 1.25, math.inf))

    def test_cpp_uses_wide_math_atomic_commits(self):
        code = (ROOT / "servers/physics_xpbd_strain_limit.h").read_text()
        self.assertIn("double(next_b.x) - double(next_a.x)", code)
        self.assertIn("MIN(0.0, lambda -", code)
        self.assertIn("const Vector3 projected_a{", code)
        self.assertIn("if (!projected_a.is_finite() || !projected_b.is_finite())", code)
        self.assertLess(code.index("if (!projected_a.is_finite()"),
                        code.index("r_a = next_a;"))
        self.assertIn("r_lambdas = next_lambdas;", code)

    def test_settings_solver_and_cleanup_are_wired(self):
        body = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.cpp").read_text()
        space = (ROOT / "modules/godot_physics_3d/godot_space_3d.cpp").read_text()
        server = (ROOT / "servers/physics_3d/physics_server_3d.cpp").read_text()
        header = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.h").read_text()
        for field in ("soft_body_xpbd_strain_max_stretch_ratio",
                      "soft_body_xpbd_strain_min_compression_ratio",
                      "soft_body_xpbd_strain_limit_compliance"):
            self.assertIn(field, server)
            self.assertIn(field, space)
        self.assertIn("physics_xpbd_solve_strain_limits(", body)
        self.assertIn("xpbd_strain_lambdas.resize(links.size())", body)
        self.assertIn("xpbd_strain_lambdas.reset();", body)
        self.assertIn("LocalVector<PhysicsXPBDStrainLimitLambdas>", header)


if __name__ == "__main__":
    unittest.main()
