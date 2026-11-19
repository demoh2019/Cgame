"""StVK surface membrane XPBD: numerical reference and engine source contracts.

Run:
  python3 -m unittest discover -s tests/stress -p test_physics_xpbd_membrane.py -v
Native checks: tests/servers/test_physics_xpbd_membrane.cpp

Passing these reference tests is not equivalent to a full Godot build.
"""

import math
from pathlib import Path
import random
import unittest

ROOT = Path(__file__).resolve().parents[2]


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1],
            a[2] * b[0] - a[0] * b[2],
            a[0] * b[1] - a[1] * b[0])


def rest_metric(a, b, c):
    ab = [b[i] - a[i] for i in range(3)]
    ac = [c[i] - a[i] for i in range(3)]
    length_squared = dot(ab, ab)
    cross_squared = dot(cross(ab, ac), cross(ab, ac))
    if not (length_squared > 0 and
            cross_squared > length_squared * dot(ac, ac) * 1e-16):
        return None
    length = math.sqrt(length_squared)
    height = math.sqrt(cross_squared) / length
    along = dot(ab, ac) / length
    return (1 / length, -along / (length * height), 1 / height,
            0.5 * length * height)


def evaluate(rest, a, b, c, poisson=0.3):
    inv_u, q, inv_height, area = rest
    ab = [b[i] - a[i] for i in range(3)]
    ac = [c[i] - a[i] for i in range(3)]
    f0 = [inv_u * v for v in ab]
    f1 = [q * ab[i] + inv_height * ac[i] for i in range(3)]
    e00 = 0.5 * (dot(f0, f0) - 1)
    e11 = 0.5 * (dot(f1, f1) - 1)
    e01 = 0.5 * dot(f0, f1)
    trace = e00 + e11
    mu = 0.5 / (1 + poisson)
    lame = poisson / (1 - poisson * poisson)
    energy = area * (mu * (e00 * e00 + e11 * e11 + 2 * e01 * e01) +
                     0.5 * lame * trace * trace)
    s00 = lame * trace + 2 * mu * e00
    s11 = lame * trace + 2 * mu * e11
    s01 = 2 * mu * e01
    p0 = [f0[i] * s00 + f1[i] * s01 for i in range(3)]
    p1 = [f0[i] * s01 + f1[i] * s11 for i in range(3)]
    gb = [area * (inv_u * p0[i] + q * p1[i]) for i in range(3)]
    gc = [area * inv_height * p1[i] for i in range(3)]
    ga = [-gb[i] - gc[i] for i in range(3)]
    return energy, (ga, gb, gc)


def solve(rest, a, b, c, inv=(0, 1, 1), poisson=0.3, alpha=0, lagrange=0):
    energy, grads = evaluate(rest, a, b, c, poisson)
    if not (energy > 0 and math.isfinite(energy)):
        return None
    value = math.sqrt(2 * energy)
    gradients = [[p / value for p in vertex] for vertex in grads]
    weighted = sum(inv[j] * dot(gradients[j], gradients[j]) for j in range(3))
    if not (weighted > 0 and math.isfinite(weighted)):
        return None
    dlam = -(value + alpha * lagrange) / (weighted + alpha)
    output = [[old[k] + inv[j] * dlam * gradients[j][k] for k in range(3)]
              for j, old in enumerate((a, b, c))]
    if not all(math.isfinite(x) for point in output for x in point):
        return None
    return output, lagrange + dlam


class XPBDMembraneContracts(unittest.TestCase):
    def test_rest_metric_geometry(self):
        rest = rest_metric((0, 0, 0), (1, 0, 0), (0, 1, 0))
        self.assertEqual(rest, (1, 0, 1, 0.5))
        self.assertIsNone(rest_metric((0, 0, 0), (1, 0, 0), (2, 0, 0)))

    def test_rigid_translation_and_rotation_cost_zero(self):
        rest = rest_metric((0, 0, 0), (1, 0, 0), (0, 1, 0))
        self.assertEqual(evaluate(rest, (0, 0, 0), (1, 0, 0), (0, 1, 0))[0], 0)
        self.assertEqual(evaluate(rest, (3, 4, 5), (3, 5, 5), (2, 4, 5))[0], 0)

    def test_tension_and_compression_project_towards_rest(self):
        rest = rest_metric((0, 0, 0), (1, 0, 0), (0, 1, 0))
        for x in (0.6, 1.5):
            a = [0, 0, 0]
            b = [x, 0, 0]
            c = [0, 1, 0]
            before = evaluate(rest, a, b, c)[0]
            out, _ = solve(rest, a, b, c, inv=(0, 1, 0))
            self.assertLess(evaluate(rest, *out)[0], before)
            self.assertEqual(out[0], a)
            self.assertEqual(out[2], c)

    def test_poisson_ratio_couples_tangent_strains(self):
        rest = rest_metric((0, 0, 0), (1, 0, 0), (0, 1, 0))
        vertices = ((0, 0, 0), (1.4, 0, 0), (0.3, 1, 0))
        a = solve(rest, *vertices, poisson=0.0)
        b = solve(rest, *vertices, poisson=0.45)
        self.assertGreater(abs(a[0][2][1] - b[0][2][1]), 0.02)

    def test_analytic_gradients_vs_centered_differences(self):
        rng = random.Random(20261119)
        for _ in range(350):
            rest = rest_metric((0, 0, 0), (1, 0, 0), (0, 1, 0))
            verts = [[0, 0, 0],
                     [rng.uniform(.6, 1.8), rng.uniform(-.3, .3), rng.uniform(-.2, .2)],
                     [rng.uniform(-.3, .3), rng.uniform(.6, 1.8), rng.uniform(-.2, .2)]]
            e, gradients = evaluate(rest, *verts)
            self.assertTrue(math.isfinite(e) and e >= 0)
            for j in range(3):
                for k in range(3):
                    eps = 1e-6
                    plus = [x.copy() for x in verts]
                    minus = [x.copy() for x in verts]
                    plus[j][k] += eps
                    minus[j][k] -= eps
                    finite = (evaluate(rest, *plus)[0] - evaluate(rest, *minus)[0]) / (2 * eps)
                    self.assertAlmostEqual(gradients[j][k], finite, delta=1e-7)

    def test_random_scales_pins_and_finite_outputs(self):
        rng = random.Random(961714)
        for _ in range(2500):
            scale = 10 ** rng.uniform(-9, 20)
            rest = rest_metric((0, 0, 0), (scale, 0, 0), (0, scale, 0))
            a, b, c = ((0, 0, 0), (scale * rng.uniform(.7, 1.3), 0, 0),
                       (scale * rng.uniform(-.15, .15), scale * rng.uniform(.7, 1.3), 0))
            out = solve(rest, a, b, c, inv=(0, 1, 1), poisson=rng.uniform(-.45, .45))
            if out is None:
                # Exactly unstrained configurations are allowed to skip.
                continue
            points, lagrange = out
            self.assertEqual(points[0], [0, 0, 0])
            self.assertTrue(math.isfinite(lagrange))
            self.assertTrue(all(math.isfinite(v) for p in points for v in p))

    def test_rest_energy_scales_with_undeformed_area(self):
        energies = []
        for scale in (1e-3, 1, 1e3):
            rest = rest_metric((0, 0, 0), (scale, 0, 0), (0, scale, 0))
            energy, _ = evaluate(rest, (0, 0, 0), (scale * 1.25, 0, 0), (0, scale, 0))
            energies.append(energy / (scale * scale))
        self.assertAlmostEqual(energies[0], energies[1], delta=1e-12)
        self.assertAlmostEqual(energies[1], energies[2], delta=1e-12)

    def test_source_uses_analytic_stress_and_atomic_commit(self):
        h = (ROOT / "servers/physics_xpbd_membrane.h").read_text()
        self.assertIn("const double e00 = 0.5 * (f00 - 1.0);", h)
        self.assertIn("const double s01 = 2.0 * mu * e01;", h)
        self.assertIn("const double delta_lambda = -(c + p_alpha * r_lambda) / denom;", h)
        self.assertIn("if (!next_a.is_finite() || !next_b.is_finite() || !next_c.is_finite())", h)
        self.assertLess(h.index("if (!next_a.is_finite()"),
                        h.index("r_a = next_a;"))

    def test_solver_is_wired_and_opt_in(self):
        body = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.cpp").read_text()
        space = (ROOT / "modules/godot_physics_3d/godot_space_3d.cpp").read_text()
        settings = (ROOT / "servers/physics_3d/physics_server_3d.cpp").read_text()
        self.assertIn("void GodotSoftBody3D::initialize_membrane_constraints()", body)
        self.assertIn("physics_xpbd_membrane_solve(", body)
        self.assertIn("xpbd_membrane_lambdas.resize(faces.size())", body)
        self.assertIn("xpbd_membrane_lambdas.reset();", body)
        self.assertIn('"physics/3d/solver/soft_body_xpbd_membrane_compliance"', space)
        self.assertIn('"physics/3d/solver/soft_body_membrane_poisson_ratio"', space)
        self.assertIn('"physics/3d/solver/soft_body_xpbd_membrane_compliance"', settings)
        self.assertIn('"), 0.0);', settings)


if __name__ == "__main__":
    unittest.main()
