"""Independent numerical contracts for rest-frame anisotropic XPBD cloth.

Run:
    python3 -m unittest discover -s tests/stress -p 'test_physics_xpbd_anisotropic_stretch.py' -v

These tests verify numerical invariants and source wiring; native doctests
exercise the C++ kernel, and a Cgame binary is still needed for runtime checks.
"""

import math
from pathlib import Path
import random
import unittest

ROOT = Path(__file__).resolve().parents[2]


def anisotropic_alpha(delta, fiber_axis, base, parallel_ratio):
    """Compliance of a rest-mesh link for an orthotropic edge material."""
    edge_norm = math.sqrt(sum(component * component for component in delta))
    axis_norm = math.sqrt(sum(component * component for component in fiber_axis))
    if not edge_norm or not axis_norm or parallel_ratio == 1:
        return base
    cosine = sum(a * b for a, b in zip(delta, fiber_axis)) / edge_norm / axis_norm
    alignment = min(1.0, max(0.0, cosine * cosine))
    return base * (1.0 + (parallel_ratio - 1.0) * alignment)


def xpbd_project(initial_distance, rest_distance, alpha, inv_sum, iterations):
    """Mass-weighted two-particle XPBD distance projection with fixed alpha."""
    length = initial_distance
    lagrange = 0.0
    for _ in range(iterations):
        correction = (rest_distance - length - alpha * lagrange) / (inv_sum + alpha)
        length += inv_sum * correction
        lagrange += correction
    return length


class TestAnisotropicStretch(unittest.TestCase):
    def test_parallel_and_perpendicular_material_response(self):
        self.assertAlmostEqual(anisotropic_alpha((1, 0, 0), (1, 0, 0), 2, 0.2), 0.4)
        self.assertAlmostEqual(anisotropic_alpha((0, 1, 0), (1, 0, 0), 2, 0.2), 2.0)
        self.assertAlmostEqual(anisotropic_alpha((1, 1, 0), (1, 0, 0), 2, 0.2), 1.2)

    def test_default_one_is_strict_identity(self):
        rng = random.Random(0xFABC)
        for _ in range(3000):
            delta = [rng.uniform(-100, 100) for _ in range(3)]
            axis = [rng.uniform(-100, 100) for _ in range(3)]
            base = 10 ** rng.uniform(-6, 4)
            self.assertEqual(anisotropic_alpha(delta, axis, base, 1), base)

    def test_rotation_and_axis_magnitude_invariance(self):
        rng = random.Random(0x42AC)
        for _ in range(3000):
            angle = rng.uniform(-math.pi, math.pi)
            cosine, sine = math.cos(angle), math.sin(angle)
            delta = [rng.uniform(-20, 20) for _ in range(3)]
            axis = [rng.uniform(-10, 10) for _ in range(3)]
            ratio = 10 ** rng.uniform(-2, 2)
            original = anisotropic_alpha(delta, axis, 0.5, ratio)
            turn = lambda v: (v[0] * cosine - v[1] * sine,
                              v[0] * sine + v[1] * cosine, v[2])
            rotated = anisotropic_alpha(turn(delta), turn(axis), 0.5, ratio)
            scaled = anisotropic_alpha(delta, [x * 1000 for x in axis], 0.5, ratio)
            self.assertAlmostEqual(rotated, original, delta=1e-12 * (1 + abs(original)))
            self.assertAlmostEqual(scaled, original, delta=1e-12 * (1 + abs(original)))

    def test_compliance_is_bounded_by_parallel_and_perpendicular_values(self):
        rng = random.Random(0xE17)
        for _ in range(5000):
            delta = [rng.uniform(-3, 3) for _ in range(3)]
            axis = [rng.uniform(-3, 3) for _ in range(3)]
            base = 10 ** rng.uniform(-5, 3)
            ratio = 10 ** rng.uniform(-2, 2)
            alpha = anisotropic_alpha(delta, axis, base, ratio)
            self.assertTrue(math.isfinite(alpha))
            self.assertGreaterEqual(alpha, base * min(1, ratio) - 1e-10)
            self.assertLessEqual(alpha, base * max(1, ratio) + 1e-10)

    def test_fixed_step_alpha_converges_with_no_iteration_stiffness_drift(self):
        rng = random.Random(0xB11E)
        for _ in range(1000):
            base = 10 ** rng.uniform(-4, 2)
            ratio = 10 ** rng.uniform(-2, 2)
            alpha = anisotropic_alpha((1, 2, 1), (1, 0, 0), base, ratio)
            initial = rng.uniform(0.05, 5)
            inv_sum = rng.uniform(0.01, 4)
            solved = xpbd_project(initial, 1, alpha, inv_sum, 20)
            exact = (alpha * initial + inv_sum) / (inv_sum + alpha)
            self.assertAlmostEqual(solved, exact, delta=1e-10 * (1 + abs(exact)))

    def test_source_wiring_and_off_by_default(self):
        server = (ROOT / "servers/physics_3d/physics_server_3d.cpp").read_text()
        space_h = (ROOT / "modules/godot_physics_3d/godot_space_3d.h").read_text()
        space_cpp = (ROOT / "modules/godot_physics_3d/godot_space_3d.cpp").read_text()
        body = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.cpp").read_text()
        kernel = (ROOT / "servers/physics_xpbd_anisotropic_stretch.h").read_text()
        self.assertIn("soft_body_xpbd_parallel_compliance_ratio", server)
        self.assertIn("soft_body_xpbd_material_axis", server)
        self.assertIn("soft_body_xpbd_parallel_compliance_ratio = 1.0;", space_h)
        self.assertIn("get_soft_body_xpbd_material_axis()", space_h)
        self.assertIn('GLOBAL_GET("physics/3d/solver/soft_body_xpbd_material_axis")', space_cpp)
        self.assertIn("const bool use_anisotropic_stretch = use_xpbd && parallel_ratio != real_t(1.0)", body)
        self.assertIn("if (use_tension_hardening || use_compression_hardening || use_anisotropic_stretch || use_fatigue)", body)
        self.assertIn("physics_xpbd_anisotropic_stretch_alpha(link.n[0]->s, link.n[1]->s", body)
        self.assertIn("physics_xpbd_anisotropic_stretch_alpha(", kernel)
        self.assertLess(
            body.index("physics_xpbd_anisotropic_stretch_alpha(link.n[0]->s"),
            body.index("for (int isolve = 0; isolve < iteration_count; ++isolve)"),
        )


if __name__ == "__main__":
    unittest.main()
