"""Mathematical and source regressions for the optional 3D contact block solver.

These verify the two-contact complementarity equations with 3D tensor
inertia. They are not a substitute for native compilation or a real stack
simulation in the engine.
"""

from pathlib import Path
import math
import random
import unittest

ROOT = Path(__file__).resolve().parents[2]
BODY_PAIR = ROOT / "modules/godot_physics_3d/godot_body_pair_3d.cpp"
SPACE = ROOT / "modules/godot_physics_3d/godot_space_3d.cpp"
HEADER = ROOT / "modules/godot_physics_3d/godot_space_3d.h"
SETTINGS = ROOT / "servers/physics_3d/physics_server_3d.cpp"


def dot(a: tuple[float, float, float], b: tuple[float, float, float]) -> float:
    return sum(x * y for x, y in zip(a, b))


def cross(a: tuple[float, float, float], b: tuple[float, float, float]) -> tuple[float, float, float]:
    return (
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    )


def diag_apply(diagonal: tuple[float, float, float], v: tuple[float, float, float]) -> tuple[float, float, float]:
    return tuple(x * y for x, y in zip(diagonal, v))


def effective_mass(
    normal: tuple[float, float, float],
    r_a: tuple[tuple[float, float, float], tuple[float, float, float]],
    r_b: tuple[tuple[float, float, float], tuple[float, float, float]],
    inertia_a: tuple[float, float, float],
    inertia_b: tuple[float, float, float],
    inv_mass: float,
) -> tuple[float, float, float]:
    ra0, ra1 = (cross(r, normal) for r in r_a)
    rb0, rb1 = (cross(r, normal) for r in r_b)
    k00 = inv_mass + dot(ra0, diag_apply(inertia_a, ra0)) + dot(rb0, diag_apply(inertia_b, rb0))
    k01 = inv_mass + dot(ra0, diag_apply(inertia_a, ra1)) + dot(rb0, diag_apply(inertia_b, rb1))
    k11 = inv_mass + dot(ra1, diag_apply(inertia_a, ra1)) + dot(rb1, diag_apply(inertia_b, rb1))
    return k00, k01, k11


def solve_lcp(k00: float, k01: float, k11: float, b0: float, b1: float) -> tuple[float, float] | None:
    det = k00 * k11 - k01 * k01
    if k00 <= 0 or k11 <= 0 or det <= 1e-6 or max(k00, k11) ** 2 >= 100 * det:
        return None
    next0 = -(k11 * b0 - k01 * b1) / det
    next1 = -(k00 * b1 - k01 * b0) / det
    if next0 >= 0 and next1 >= 0:
        return next0, next1
    next0, next1 = 0.0, -b1 / k11
    if next1 >= 0 and k01 * next1 + b0 >= 0:
        return next0, next1
    next0, next1 = -b0 / k00, 0.0
    if next0 >= 0 and k01 * next0 + b1 >= 0:
        return next0, next1
    if b0 >= 0 and b1 >= 0:
        return 0.0, 0.0
    return None


class CoupledContact3DTests(unittest.TestCase):
    def test_all_complementarity_cases(self) -> None:
        matrix = (2.0, 0.5, 3.0)
        for expected, loads in (
            ((1.0, 2.0), (-3.0, -6.5)),
            ((0.0, 1.0), (2.0, -3.0)),
            ((2.0, 0.0), (-4.0, 3.0)),
            ((0.0, 0.0), (1.0, 2.0)),
        ):
            solved = solve_lcp(*matrix, *loads)
            self.assertIsNotNone(solved)
            self.assertAlmostEqual(solved[0], expected[0])
            self.assertAlmostEqual(solved[1], expected[1])

    def test_singular_matrix_uses_old_solver(self) -> None:
        self.assertIsNone(solve_lcp(2.0, 2.0, 2.0, -1.0, -1.0))
        self.assertIsNone(solve_lcp(0.0, 0.0, 0.0, -1.0, -1.0))

    def test_random_3d_tensor_inertia_matrices(self) -> None:
        rng = random.Random(20261119)
        solved_count = 0
        for _ in range(6000):
            n = [rng.uniform(-1, 1) for _ in range(3)]
            norm = math.sqrt(dot(n, n))
            if norm < 1e-6:
                continue
            normal = tuple(x / norm for x in n)
            rand_vec = lambda: tuple(rng.uniform(-2.0, 2.0) for _ in range(3))
            ra = (rand_vec(), rand_vec())
            rb = (rand_vec(), rand_vec())
            ia = tuple(rng.uniform(0.0, 3.0) for _ in range(3))
            ib = tuple(rng.uniform(0.0, 3.0) for _ in range(3))
            k00, k01, k11 = effective_mass(normal, ra, rb, ia, ib, rng.uniform(0.0, 3.0))
            old0, old1 = rng.uniform(0, 3), rng.uniform(0, 3)
            vn0, vn1 = rng.uniform(-4.0, 4.0), rng.uniform(-4.0, 4.0)
            b0 = vn0 - k00 * old0 - k01 * old1
            b1 = vn1 - k01 * old0 - k11 * old1
            result = solve_lcp(k00, k01, k11, b0, b1)
            if result is None:
                continue
            x0, x1 = result
            w0 = k00 * x0 + k01 * x1 + b0
            w1 = k01 * x0 + k11 * x1 + b1
            eps = 1e-7 * max(1, abs(b0), abs(b1))
            self.assertGreaterEqual(x0, -eps)
            self.assertGreaterEqual(x1, -eps)
            self.assertGreaterEqual(w0, -eps)
            self.assertGreaterEqual(w1, -eps)
            self.assertLessEqual(abs(x0 * w0), eps * max(1, x0))
            self.assertLessEqual(abs(x1 * w1), eps * max(1, x1))
            solved_count += 1
        self.assertGreater(solved_count, 3000)

    def test_opt_in_source_contract(self) -> None:
        source = BODY_PAIR.read_text(encoding="utf-8")
        space = SPACE.read_text(encoding="utf-8")
        header = HEADER.read_text(encoding="utf-8")
        registered = SETTINGS.read_text(encoding="utf-8")
        self.assertIn('"physics/3d/solver/block_solver_enabled"), false', registered)
        self.assertIn('GLOBAL_GET("physics/3d/solver/block_solver_enabled")', space)
        self.assertIn("is_block_solver_enabled() const", header)
        for snippet in (
            "space->is_block_solver_enabled() && contact_count == 2",
            "contacts[0].normal.dot(contacts[1].normal) > real_t(0.9999)",
            "const real_t det = k00 * k11 - k01 * k01;",
            "largest * largest < real_t(100.0) * det",
            "Math::is_finite(det)",
            "Math::is_finite(next0) && Math::is_finite(next1)",
            "valid = b0 >= 0.0 && b1 >= 0.0;",
            "if (block_solved)",
            "c0.acc_impulse -= impulse;",
            "c1.acc_impulse -= impulse;",
        ):
            self.assertIn(snippet, source)


if __name__ == "__main__":
    unittest.main()
