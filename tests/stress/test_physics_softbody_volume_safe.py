"""Numerical and source regression contracts for closed SoftBody volume scaling.

Run:
 python3 -m unittest discover -s tests/stress -p 'test_physics_softbody_volume_safe.py' -v

Native counterparts: tests/servers/test_physics_softbody_volume_safe.cpp
"""
import math
from pathlib import Path
import struct
import unittest

ROOT = Path(__file__).resolve().parents[2]


def f32(value):
    try:
        return struct.unpack("<f", struct.pack("<f", float(value)))[0]
    except OverflowError:
        return math.copysign(math.inf, value)


def valid_volume(volume, extent):
    if not (math.isfinite(volume) and math.isfinite(extent)) or extent <= 0:
        return False
    cube = extent * extent * extent
    return math.isfinite(cube) and cube > 0 and abs(volume / cube) > 1e-10


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1],
            a[2] * b[0] - a[0] * b[2],
            a[0] * b[1] - a[1] * b[0])


class SoftBodyVolumeScaleContracts(unittest.TestCase):
    def test_uniform_rescaling_keeps_valid_tetra_valid(self):
        for length in (1e-6, 1e-3, 1.0, 1e3, 1e20):
            self.assertTrue(valid_volume(length ** 3 / 6, length))
            self.assertTrue(valid_volume(-length ** 3 / 6, length))

    def test_flat_and_invalid_geometry_is_rejected(self):
        self.assertFalse(valid_volume(0.0, 1.0))
        self.assertFalse(valid_volume(1e-12, 1.0))
        self.assertFalse(valid_volume(1.0, 0.0))
        self.assertFalse(valid_volume(1.0, float("inf")))

    def test_float32_coordinate_difference_overflow_repro(self):
        high = f32(1e38)
        tiny = f32(1e-10)
        self.assertTrue(math.isinf(f32(high - (-high))))
        # A cross-product of those finite vertices still has a
        # representable gradient when intermediate operations use doubles.
        a = (-float(high), 0.0, 0.0)
        b = (float(high), 0.0, 0.0)
        c = (float(high), float(tiny), 0.0)
        ga = cross(b, c)
        gb = cross(c, a)
        self.assertTrue(math.isfinite(f32(ga[2] / 6)))
        self.assertTrue(math.isfinite(f32(gb[2] / 6)))
        self.assertGreater(ga[2], 0.0)
        self.assertGreater(gb[2], 0.0)

    def test_solver_uses_scale_normalization_instead_of_absolute_epsilon(self):
        code = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.cpp").read_text()
        self.assertIn("physics_softbody_volume_is_non_degenerate(volume, axis_extent)", code)
        self.assertNotIn("Math::abs(volume) <= double(CMP_EPSILON)", code)
        self.assertIn("physics_softbody_volume_face_gradients(", code)
        self.assertIn('#include "servers/physics_softbody_volume_safe.h"', code)

    def test_gradient_helper_checks_all_values_before_mutating_output(self):
        header = (ROOT / "servers/physics_softbody_volume_safe.h").read_text()
        self.assertIn("double(p_a.x) - double(p_origin.x)", header)
        self.assertIn("double(p_b.y) - double(p_origin.y)", header)
        self.assertIn("const Vector3 ga(", header)
        self.assertIn("if (!ga.is_finite() || !gb.is_finite() || !gc.is_finite())", header)
        self.assertLess(header.index("if (!ga.is_finite()"), header.index("r_grad_a = ga;"))

    def test_xpbd_area_tethers_and_plasticity_survive(self):
        body = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.cpp").read_text()
        self.assertIn("physics_softbody_creep_rest_length(", body)
        self.assertIn("physics_xpbd_solve_triangle_area(", body)
        self.assertIn("xpbd_tethers_dirty", body)
        self.assertIn("solve_volume_constraint(double p_alpha, double &r_lambda)", body)
        native = (ROOT / "tests/servers/test_physics_softbody_volume_safe.cpp").read_text()
        self.assertEqual(native.count('TEST_CASE("[PhysicsVolume]'), 6)


if __name__ == "__main__":
    unittest.main()
