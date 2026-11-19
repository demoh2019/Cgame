"""Jolt-style 3D gyroscopic free rotation source and reference regressions.

The numerical reference implements Euler's free-rigid-body angular momentum
equation in principal coordinates, followed by the momentum normalization
used by Jolt Physics. Engine C++ builds and runtime tests remain separate.
"""

import math
import random
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "servers/physics_gyroscopic_3d.h"
BODY = ROOT / "modules/godot_physics_3d/godot_body_3d.cpp"
SPACE_H = ROOT / "modules/godot_physics_3d/godot_space_3d.h"
SPACE_CPP = ROOT / "modules/godot_physics_3d/godot_space_3d.cpp"
SERVER = ROOT / "servers/physics_3d/physics_server_3d.cpp"
NATIVE = ROOT / "tests/servers/test_godot_physics_gyroscopic_3d.cpp"
SCENE = ROOT / "tests/stress/physics_gyroscopic_3d_regression.gd"


def cross(a, b):
    return (
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    )


def momentum(omega, inverse_inertia):
    return tuple(omega[i] / inverse_inertia[i] for i in range(3))


def length_squared(v):
    return sum(x * x for x in v)


def apply_gyroscopic(omega, inverse_inertia, step):
    if not step > 0 or any(i <= 0 for i in inverse_inertia):
        return omega
    if not all(math.isfinite(v) for v in (*omega, *inverse_inertia, step)):
        return omega
    old_momentum = momentum(omega, inverse_inertia)
    moment_change = cross(omega, old_momentum)
    if not any(moment_change):
        return omega
    new_momentum = tuple(old_momentum[i] - moment_change[i] * step for i in range(3))
    old_sq = length_squared(old_momentum)
    new_sq = length_squared(new_momentum)
    if old_sq <= 0 or new_sq <= 0 or not all(map(math.isfinite, (old_sq, new_sq))):
        return omega
    scale = math.sqrt(old_sq / new_sq)
    result = tuple(new_momentum[i] * inverse_inertia[i] * scale for i in range(3))
    return result if all(map(math.isfinite, result)) else omega


class Gyroscopic3DContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.helper = HELPER.read_text(encoding="utf-8")
        cls.body = BODY.read_text(encoding="utf-8")
        cls.space_h = SPACE_H.read_text(encoding="utf-8")
        cls.space_cpp = SPACE_CPP.read_text(encoding="utf-8")
        cls.server = SERVER.read_text(encoding="utf-8")
        cls.native = NATIVE.read_text(encoding="utf-8")
        cls.scene = SCENE.read_text(encoding="utf-8")
        a = cls.body.index("void GodotBody3D::integrate_forces(")
        b = cls.body.index("void GodotBody3D::integrate_velocities(", a)
        cls.integrator = cls.body[a:b]

    def test_opt_in_3d_only_and_default_off(self):
        self.assertIn('GLOBAL_DEF(PropertyInfo(Variant::BOOL, "physics/3d/solver/gyroscopic_forces"), false);', self.server)
        self.assertIn('gyroscopic_forces = GLOBAL_GET("physics/3d/solver/gyroscopic_forces");', self.space_cpp)
        self.assertIn("bool gyroscopic_forces = false;", self.space_h)
        self.assertIn("are_gyroscopic_forces_enabled() const", self.space_h)

    def test_only_dynamic_unlocked_rigid_bodies_receive_gyro(self):
        self.assertIn("mode == PS3DE::BODY_MODE_RIGID && get_space()->are_gyroscopic_forces_enabled()", self.integrator)
        self.assertIn("(locked_axis & ((1 << 3) | (1 << 4) | (1 << 5))) == 0", self.integrator)
        self.assertIn("principal_inertia_axes.orthonormalized()", self.integrator)
        self.assertIn("principal_frame.xform_inv(angular_velocity)", self.integrator)
        self.assertIn("principal_frame.xform(corrected_omega)", self.integrator)
        self.assertIn("GodotPhysicsGyroscopic3D::integrate_principal(", self.integrator)
        self.assertLess(self.integrator.index("angular_velocity += _inv_inertia_tensor.xform(torque) * p_step;"),
                        self.integrator.index("GodotPhysicsGyroscopic3D::integrate_principal("))

    def test_angular_momentum_is_renormalized_in_principal_coordinates(self):
        self.assertIn("const Vector3 momentum(", self.helper)
        self.assertIn("p_omega.cross(momentum) * p_step", self.helper)
        self.assertIn("const Vector3 updated_momentum = momentum - gyroscopic_change;", self.helper)
        self.assertIn("const real_t length_correction = Math::sqrt(old_squared / new_squared);", self.helper)
        self.assertIn("return corrected_omega.is_finite() ? corrected_omega : p_omega;", self.helper)

    def test_singular_and_invalid_moment_guards(self):
        self.assertIn("!(p_inv_inertia.x > 0.0)", self.helper)
        self.assertIn("!(p_inv_inertia.y > 0.0)", self.helper)
        self.assertIn("!(p_inv_inertia.z > 0.0)", self.helper)
        self.assertIn("!Math::is_finite(old_squared) || !Math::is_finite(new_squared)", self.helper)
        self.assertEqual(apply_gyroscopic((3, 5, 7), (1, 0, 2), .016), (3, 5, 7))
        self.assertEqual(apply_gyroscopic((3, 5, 7), (1, 2, 3), 0), (3, 5, 7))

    def test_isotropic_and_principal_axis_spins_are_fixed_points(self):
        self.assertEqual(apply_gyroscopic((2, -3, 7), (2, 2, 2), .016), (2, -3, 7))
        self.assertEqual(apply_gyroscopic((0, 8, 0), (.5, 1, 2), .016), (0, 8, 0))

    def test_randomized_momentum_norm_conservation(self):
        rng = random.Random(311123)
        for i in range(5000):
            omega = tuple(rng.uniform(-20, 20) for _ in range(3))
            inv = tuple(math.exp(rng.uniform(-3.0, 2.0)) for _ in range(3))
            dt = rng.uniform(1 / 240, 1 / 15)
            corrected = apply_gyroscopic(omega, inv, dt)
            old_norm = length_squared(momentum(omega, inv))
            new_norm = length_squared(momentum(corrected, inv))
            with self.subTest(case=i):
                self.assertTrue(all(math.isfinite(x) for x in corrected))
                self.assertAlmostEqual(old_norm, new_norm, delta=max(1.0, old_norm) * 1e-12)

    def test_asymmetric_spin_changes_direction_without_unbounded_momentum(self):
        omega = (6.0, 9.0, 14.0)
        inv = (.25, .5, 1.0)
        initial_squared = length_squared(momentum(omega, inv))
        changed = False
        for _ in range(600):
            new = apply_gyroscopic(omega, inv, 1 / 120)
            changed |= new != omega
            omega = new
            self.assertAlmostEqual(length_squared(momentum(omega, inv)),
                                   initial_squared, delta=initial_squared * 1e-10)
        self.assertTrue(changed)

    def test_native_and_engine_runtime_regressions(self):
        self.assertEqual(self.native.count('TEST_CASE("[GodotPhysics3D]'), 5)
        self.assertIn("_run_case(false)", self.scene)
        self.assertIn("_run_case(true)", self.scene)
        self.assertIn("BODY_PARAM_INERTIA, INERTIA", self.scene)
        self.assertIn("max_momentum_error", self.scene)


if __name__ == "__main__":
    unittest.main()
