"""Implicit midpoint gyroscope source contracts and numerical reference.

The new (optional) midpoint method solves the torque-free Euler angular
momentum equation via a local 3x3 Newton step. A converged update preserves
both the norm of angular momentum and rotational energy. This Python model
only validates numerical properties; the native C++ and engine runtime
regressions must be run separately on a compiled Cgame binary.
"""

import math
import random
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
GYRO = ROOT / "servers/physics_gyroscopic_3d.h"
BODY = ROOT / "modules/godot_physics_3d/godot_body_3d.cpp"
SPACE_H = ROOT / "modules/godot_physics_3d/godot_space_3d.h"
SPACE_CPP = ROOT / "modules/godot_physics_3d/godot_space_3d.cpp"
SERVER = ROOT / "servers/physics_3d/physics_server_3d.cpp"
NATIVE = ROOT / "tests/servers/test_godot_physics_gyroscopic_midpoint_3d.cpp"
SCENE = ROOT / "tests/stress/physics_gyroscopic_midpoint_3d_regression.gd"


def cross(a, b):
    return (
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    )


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def vector_add(a, b):
    return tuple(x + y for x, y in zip(a, b))


def vector_sub(a, b):
    return tuple(x - y for x, y in zip(a, b))


def scale(v, k):
    return tuple(x * k for x in v)


def linear_solve(columns, rhs):
    # Independent 3x3 Gaussian elimination reference; Basis::inverse()
    # in Cgame solves the same Newton system in C++.
    matrix = [[columns[j][i] for j in range(3)] + [rhs[i]]
              for i in range(3)]
    for pivot in range(3):
        chosen = max(range(pivot, 3), key=lambda i: abs(matrix[i][pivot]))
        if abs(matrix[chosen][pivot]) <= 1e-6:
            return None
        matrix[pivot], matrix[chosen] = matrix[chosen], matrix[pivot]
        factor = matrix[pivot][pivot]
        for j in range(pivot, 4):
            matrix[pivot][j] /= factor
        for i in range(3):
            if i == pivot:
                continue
            factor = matrix[i][pivot]
            for j in range(pivot, 4):
                matrix[i][j] -= factor * matrix[pivot][j]
    return tuple(row[3] for row in matrix)


def midpoint_reference(omega, inverse_inertia, step):
    if step <= 0 or any(i <= 0 for i in inverse_inertia):
        return omega, False
    if not all(map(math.isfinite, (*omega, *inverse_inertia, step))):
        return omega, False
    old = tuple(w / inv for w, inv in zip(omega, inverse_inertia))
    original_change = cross(old, omega)
    if original_change == (0.0, 0.0, 0.0):
        return omega, True
    next_l = vector_add(old, scale(original_change, step))
    tolerance = 1e-12 * max(1.0, dot(old, old))
    for _ in range(8):
        mid = scale(vector_add(old, next_l), 0.5)
        mid_omega = tuple(v * inv for v, inv in zip(mid, inverse_inertia))
        residual = vector_sub(vector_sub(next_l, old), scale(cross(mid, mid_omega), step))
        if dot(residual, residual) <= tolerance:
            return tuple(v * inv for v, inv in zip(next_l, inverse_inertia)), True
        columns = []
        for j in range(3):
            basis = tuple(float(i == j) for i in range(3))
            term = vector_add(cross(basis, mid_omega),
                              cross(mid, scale(basis, inverse_inertia[j])))
            columns.append(vector_sub(basis, scale(term, step * 0.5)))
        correction = linear_solve(columns, residual)
        if correction is None:
            break
        next_l = vector_sub(next_l, correction)
        if not all(map(math.isfinite, next_l)):
            break
    return omega, False


def invariants(omega, inv):
    momentum = tuple(w / i for w, i in zip(omega, inv))
    return dot(momentum, momentum), 0.5 * dot(momentum, omega)


class ImplicitMidpointGyroscopic3DContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.gyro = GYRO.read_text(encoding="utf-8")
        cls.body = BODY.read_text(encoding="utf-8")
        cls.space_h = SPACE_H.read_text(encoding="utf-8")
        cls.space_cpp = SPACE_CPP.read_text(encoding="utf-8")
        cls.server = SERVER.read_text(encoding="utf-8")
        cls.native = NATIVE.read_text(encoding="utf-8")
        cls.scene = SCENE.read_text(encoding="utf-8")

    def test_opt_in_mode_preserves_existing_default(self):
        self.assertIn('GLOBAL_DEF(PropertyInfo(Variant::INT, "physics/3d/solver/gyroscopic_integration_mode", PROPERTY_HINT_ENUM, "Normalized Euler,Implicit Midpoint"), 0);', self.server)
        self.assertIn('gyroscopic_integration_mode = CLAMP((int)GLOBAL_GET("physics/3d/solver/gyroscopic_integration_mode"), 0, 1);', self.space_cpp)
        self.assertIn("int gyroscopic_integration_mode = 0;", self.space_h)
        self.assertIn("get_gyroscopic_integration_mode() const", self.space_h)
        self.assertIn("bool gyroscopic_forces = false;", self.space_h)

    def test_integration_selects_midpoint_only_when_requested(self):
        self.assertIn("get_space()->get_gyroscopic_integration_mode() == 1 ?", self.body)
        self.assertIn("GodotPhysicsGyroscopic3D::integrate_principal_midpoint(", self.body)
        self.assertIn("GodotPhysicsGyroscopic3D::integrate_principal(", self.body)
        self.assertIn("are_gyroscopic_forces_enabled()", self.body)
        self.assertIn("(locked_axis & ((1 << 3) | (1 << 4) | (1 << 5))) == 0", self.body)

    def test_midpoint_newton_system_and_fallback(self):
        self.assertIn("static _FORCE_INLINE_ Vector3 integrate_principal_midpoint(", self.gyro)
        self.assertIn("mid_momentum.cross(mid_omega) * p_step", self.gyro)
        self.assertIn("const Basis jacobian(column_x, column_y, column_z);", self.gyro)
        self.assertIn("jacobian.inverse().xform(residual)", self.gyro)
        self.assertIn("for (int iteration = 0; iteration < 8; iteration++)", self.gyro)
        self.assertIn("return integrate_principal(p_omega, p_inv_inertia, p_step);", self.gyro)

    def test_isotropic_and_principal_spin_are_identity(self):
        omega = (3.0, -4.0, 5.0)
        self.assertEqual(midpoint_reference(omega, (1.0, 1.0, 1.0), .02), (omega, True))
        principal = (0.0, 12.0, 0.0)
        self.assertEqual(midpoint_reference(principal, (.25, .5, 1), .02), (principal, True))

    def test_invalid_inertia_and_step_do_not_produce_torque(self):
        w = (3.0, 4.0, 5.0)
        for inverse_inertia, step in [
            ((0, 1, 1), .01),
            ((-1, 1, 1), .01),
            ((1, 1, 1), 0),
            ((1, 1, 1), -1),
        ]:
            with self.subTest(inverse_inertia=inverse_inertia, step=step):
                self.assertEqual(midpoint_reference(w, inverse_inertia, step), (w, False))

    def test_random_inertia_conserves_energy_and_momentum_when_converged(self):
        rng = random.Random(20261119)
        converged = 0
        for case in range(2000):
            omega = tuple(rng.uniform(-20.0, 20.0) for _ in range(3))
            inv = tuple(math.exp(rng.uniform(-3.0, 2.0)) for _ in range(3))
            step = rng.uniform(1 / 240, 1 / 15)
            next_omega, success = midpoint_reference(omega, inv, step)
            if not success:
                continue
            converged += 1
            old_l2, old_energy = invariants(omega, inv)
            next_l2, next_energy = invariants(next_omega, inv)
            with self.subTest(case=case):
                self.assertAlmostEqual(old_l2, next_l2, delta=old_l2 * 2e-5)
                self.assertAlmostEqual(old_energy, next_energy, delta=old_energy * 2e-5)
        self.assertGreater(converged, 1800)

    def test_long_torque_free_rotation_has_small_energy_drift(self):
        inv = (.25, .5, 1.0)
        omega = (6.0, 9.0, 14.0)
        initial_momentum, initial_energy = invariants(omega, inv)
        for step in range(600):
            next_omega, success = midpoint_reference(omega, inv, 1 / 120)
            self.assertTrue(success, msg=f"Midpoint solver failed on step {step}")
            omega = next_omega
        final_momentum, final_energy = invariants(omega, inv)
        self.assertLess(abs(final_momentum - initial_momentum) / initial_momentum, 1e-4)
        self.assertLess(abs(final_energy - initial_energy) / initial_energy, 1e-4)

    def test_native_and_runtime_regressions(self):
        self.assertEqual(self.native.count('TEST_CASE("[GodotPhysics3D]'), 5)
        self.assertIn("_exercise(0)", self.scene)
        self.assertIn("_exercise(1)", self.scene)
        self.assertIn("peak_energy_error", self.scene)
        self.assertIn("peak_momentum_error", self.scene)


if __name__ == "__main__":
    unittest.main()
