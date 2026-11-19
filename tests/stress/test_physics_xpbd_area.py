"""Contracts and geometric reference tests for XPBD soft-body triangle area.

Source tests require no compiled editor; the paired GDScript stress workload
runs real gravity, pinned cloth, and per-space area compliance on Cgame.
"""

import math
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
STRESS = ROOT / "tests/stress"


def sub(a, b):
    return tuple(x - y for x, y in zip(a, b))


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1],
            a[2] * b[0] - a[0] * b[2],
            a[0] * b[1] - a[1] * b[0])


def area(a, b, c):
    cr = cross(sub(b, a), sub(c, a))
    return 0.5 * math.sqrt(sum(x * x for x in cr))


def gradients(a, b, c):
    ab, ac = sub(b, a), sub(c, a)
    raw_normal = cross(ab, ac)
    norm = math.sqrt(sum(x * x for x in raw_normal))
    normal = tuple(x / norm for x in raw_normal)
    return (
        tuple(0.5 * x for x in cross(sub(b, c), normal)),
        tuple(0.5 * x for x in cross(ac, normal)),
        tuple(0.5 * x for x in cross(normal, ab)),
    )


class SoftBodyXPBDAreaContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.helper = (ROOT / "servers/physics_xpbd_area.h").read_text(encoding="utf-8")
        cls.cpp = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.cpp").read_text(encoding="utf-8")
        cls.header = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.h").read_text(encoding="utf-8")
        cls.space = (ROOT / "modules/godot_physics_3d/godot_space_3d.cpp").read_text(encoding="utf-8")
        cls.space_h = (ROOT / "modules/godot_physics_3d/godot_space_3d.h").read_text(encoding="utf-8")
        cls.settings = (ROOT / "servers/physics_3d/physics_server_3d.cpp").read_text(encoding="utf-8")

    def test_gradients_agree_with_finite_differences(self):
        a, b, c = (0.1, 0.2, 0.0), (2.0, -0.1, 0.3), (1.0, 1.9, -0.4)
        analytical = gradients(a, b, c)
        for vertex in range(3):
            for axis in range(3):
                points = [list(a), list(b), list(c)]
                h = 1e-6
                points[vertex][axis] += h
                plus = area(*points)
                points[vertex][axis] -= 2 * h
                minus = area(*points)
                self.assertAlmostEqual(analytical[vertex][axis], (plus - minus) / (2 * h), delta=1e-6)

    def test_one_step_preserves_pins_and_reduces_area_error(self):
        points = [(0.0, 0.0, 0.0), (2.0, 0.0, 0.0), (1.0, 1.2, 0.0)]
        inv_mass = [0.0, 0.0, 3.0]
        rest_area, alpha, lagrange = 2.0, 0.0036, 0.0
        before = abs(area(*points) - rest_area)
        g = gradients(*points)
        denominator = alpha + sum(w * sum(x*x for x in gi) for w, gi in zip(inv_mass, g))
        d_lambda = -(area(*points) - rest_area + alpha * lagrange) / denominator
        changed = [tuple(x + w * d_lambda * dx for x, dx in zip(p, gi))
                   for p, gi, w in zip(points, g, inv_mass)]
        self.assertEqual(points[:2], changed[:2])
        self.assertLess(abs(area(*changed) - rest_area), before)

    def test_source_validates_inputs_and_never_moves_pinned_nodes(self):
        self.assertIn("physics_xpbd_solve_triangle_area(", self.helper)
        self.assertIn("p_inv_mass_a < 0.0", self.helper)
        self.assertIn("!(twice_area > CMP_EPSILON)", self.helper)
        self.assertIn("p_inv_mass_a * grad_a.length_squared()", self.helper)
        self.assertIn("p_inv_mass_b * grad_b.length_squared()", self.helper)
        self.assertIn("p_inv_mass_c * grad_c.length_squared()", self.helper)
        self.assertIn("const double delta_lambda = (-area_error - double(p_alpha) * double(r_lambda)) / denominator;", self.helper)
        self.assertIn("const Vector3 next_a = r_a + grad_a * real_t(double(p_inv_mass_a) * delta_lambda);", self.helper)
        self.assertIn("if (!next_a.is_finite() || !next_b.is_finite() || !next_c.is_finite())", self.helper)

    def test_opt_in_solver_integrates_area_per_iteration_and_releases_buffers(self):
        self.assertIn('#include "servers/physics_xpbd_area.h"', self.cpp)
        self.assertIn("LocalVector<real_t> xpbd_area_lambdas;", self.header)
        self.assertIn("get_soft_body_xpbd_area_compliance()", self.space_h)
        self.assertIn('GLOBAL_GET("physics/3d/solver/soft_body_xpbd_area_compliance")', self.space)
        self.assertIn('GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/soft_body_xpbd_area_compliance"', self.settings)
        self.assertIn("const bool use_area_xpbd =", self.cpp)
        self.assertIn("xpbd_area_lambdas.resize(faces.size());", self.cpp)
        self.assertIn("physics_xpbd_solve_triangle_area(", self.cpp)
        self.assertIn("face.ra, area_alpha, xpbd_area_lambdas[face_index]", self.cpp)
        self.assertIn("xpbd_area_lambdas.reset();", self.cpp)
        self.assertIn("solve_links(1.0, ti);", self.cpp)

    def test_real_cloth_stress_case_is_registered(self):
        name = "physics_soft_body_xpbd_area_3d"
        self.assertIn(f'"{name}"', (STRESS / "run.py").read_text(encoding="utf-8"))
        self.assertIn(f'"{name}":', (STRESS / "stress.gd").read_text(encoding="utf-8"))
        workload = (STRESS / f"{name}.gd").read_text(encoding="utf-8")
        self.assertIn("PhysicsServer3D.soft_body_pin_point(body, 0, true)", workload)
        self.assertIn("PhysicsServer3D.soft_body_pin_point(body, 1, true)", workload)
        self.assertIn("PhysicsServer3D.soft_body_set_linear_stiffness(body, 0.0)", workload)
        self.assertIn("preserved.mean_area_error < baseline.mean_area_error * 0.5", workload)
        self.assertIn("area_preservation_verified", workload)
        self.assertIn('3d/physics_engine="GodotPhysics3D"', (STRESS / "project.godot").read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
