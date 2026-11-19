"""Numerical oracle and source contracts for opt-in XPBD triangle shear.

Run: python3 -m unittest discover -s tests/stress -p test_physics_xpbd_shear.py -v
Native counterpart: tests/servers/test_physics_xpbd_shear.cpp
"""
import math
from pathlib import Path
import random
import unittest

ROOT = Path(__file__).resolve().parents[2]


def cosine_and_gradients(points):
    a, b, c = points
    ab = [b[i] - a[i] for i in range(3)]
    ac = [c[i] - a[i] for i in range(3)]
    ab2 = sum(v * v for v in ab)
    ac2 = sum(v * v for v in ac)
    product = ab2 * ac2
    if not (math.isfinite(product) and product > 0):
        return None
    cross = (ab[1] * ac[2] - ab[2] * ac[1],
             ab[2] * ac[0] - ab[0] * ac[2],
             ab[0] * ac[1] - ab[1] * ac[0])
    cross2 = sum(v * v for v in cross)
    if not (math.isfinite(cross2) and cross2 > product * 1e-20):
        return None
    cosine = max(-1.0, min(1.0, sum(ab[i] * ac[i] for i in range(3)) /
                                math.sqrt(product)))
    gb = [ac[i] / math.sqrt(product) - cosine * ab[i] / ab2 for i in range(3)]
    gc = [ab[i] / math.sqrt(product) - cosine * ac[i] / ac2 for i in range(3)]
    ga = [-gb[i] - gc[i] for i in range(3)]
    return cosine, (ga, gb, gc)


def project(points, masses, rest_cosine, alpha, lagrange):
    geometry = cosine_and_gradients(points)
    if geometry is None:
        return None
    cosine, gradients = geometry
    weighted = sum(masses[j] * sum(v * v for v in gradients[j])
                   for j in range(3))
    denominator = weighted + alpha
    if not (weighted > 0 and math.isfinite(denominator) and denominator > 0):
        return None
    delta_lambda = -(cosine - rest_cosine + alpha * lagrange) / denominator
    new_points = [
        [points[j][i] + masses[j] * delta_lambda * gradients[j][i]
         for i in range(3)] for j in range(3)
    ]
    if not all(math.isfinite(x) for p in new_points for x in p):
        return None
    return new_points, lagrange + delta_lambda


class XPBDShearContracts(unittest.TestCase):
    def test_rest_cosine_invariant_under_scale_and_rotation(self):
        original = [[0, 0, 0], [2, 0, 0], [1, 1, 0]]
        transformed = [[100, -30, 12], [100, -24, 12], [97, -27, 12]]
        self.assertAlmostEqual(cosine_and_gradients(original)[0],
                               cosine_and_gradients(transformed)[0], places=13)

    def test_gradients_agree_with_finite_differences(self):
        rng = random.Random(20261119)
        for _ in range(100):
            points = [[0.1, -0.4, 0.2], [1.1, 0.3, -0.2],
                      [rng.uniform(0.1, 0.9), 1.5, rng.uniform(-0.5, 0.9)]]
            gradients = cosine_and_gradients(points)[1]
            for j in range(3):
                for axis in range(3):
                    step = 1e-6
                    plus = [p.copy() for p in points]
                    minus = [p.copy() for p in points]
                    plus[j][axis] += step
                    minus[j][axis] -= step
                    numeric = (cosine_and_gradients(plus)[0] -
                               cosine_and_gradients(minus)[0]) / (2 * step)
                    self.assertAlmostEqual(numeric, gradients[j][axis], delta=2e-9)

    def test_pinned_corners_and_compliant_lambda(self):
        points = [[0, 0, 0], [1, 0, 0], [0.5, 1, 0]]
        pins = [point.copy() for point in points[:2]]
        projected = project(points, (0, 0, 1), 0, 0, 0)
        self.assertIsNotNone(projected)
        self.assertEqual(projected[0][:2], pins)
        self.assertAlmostEqual(projected[0][2][0], 0, delta=1e-12)
        lagrange = 0.0
        for _ in range(30):
            result = project(points, (0, 0, 1), 0, 0.1, lagrange)
            self.assertIsNotNone(result)
            points, lagrange = result
        self.assertAlmostEqual(cosine_and_gradients(points)[0], -0.1 * lagrange,
                               delta=1e-10)

    def test_randomized_scale_stress_and_finite_pins(self):
        rng = random.Random(20261119)
        for _ in range(3000):
            scale = 10 ** rng.uniform(-8, 20)
            points = [[0.0, 0.0, 0.0], [scale, 0.0, 0.0],
                      [scale * rng.uniform(-0.75, 0.75),
                       scale * rng.uniform(0.3, 1.5),
                       scale * rng.uniform(-0.75, 0.75)]]
            result = project(points, (0, 0, 1), 0, 0, 0)
            self.assertIsNotNone(result)
            self.assertEqual(result[0][0], points[0])
            self.assertEqual(result[0][1], points[1])
            self.assertTrue(all(math.isfinite(value)
                                for vertex in result[0] for value in vertex))

    def test_degenerate_triangles_rejected(self):
        self.assertIsNone(cosine_and_gradients([[0, 0, 0], [1, 0, 0],
                                                [2, 0, 0]]))
        self.assertIsNone(project([[0, 0, 0], [1, 0, 0], [0, 1, 0]],
                                  (0, 0, 0), 0, 0, 0))

    def test_cpp_wiring_and_opt_in_memory_contract(self):
        header = (ROOT / "servers/physics_xpbd_shear.h").read_text()
        body = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.cpp").read_text()
        space = (ROOT / "modules/godot_physics_3d/godot_space_3d.cpp").read_text()
        settings = (ROOT / "servers/physics_3d/physics_server_3d.cpp").read_text()
        native = (ROOT / "tests/servers/test_physics_xpbd_shear.cpp").read_text()
        self.assertIn("double &r_lambda", header)
        self.assertIn("g.cosine * g.ab[i] / g.ab_squared", header)
        self.assertIn("if (!next_a.is_finite() || !next_b.is_finite()", header)
        self.assertIn("physics_xpbd_solve_triangle_shear(", body)
        self.assertIn("initialize_shear_constraints();", body)
        self.assertIn("xpbd_shear_lambdas.reset();", body)
        self.assertIn("soft_body_xpbd_shear_compliance", space)
        self.assertIn('"physics/3d/solver/soft_body_xpbd_shear_compliance"', settings)
        self.assertEqual(native.count('TEST_CASE("[PhysicsXPBD]'), 5)


if __name__ == "__main__":
    unittest.main()
