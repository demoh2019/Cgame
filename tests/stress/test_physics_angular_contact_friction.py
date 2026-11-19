"""Contracts and numerical reference for Bullet-style rolling/spinning friction.

The optional constraint applies at most one bounded pure-angular correction
per physics step, using the previous normal warm-start impulses as contact
load. The default zero setting keeps the classic GodotPhysics path unchanged.
Compiled engine smoke tests are still needed for full dynamics coverage.
"""

import math
import random
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "servers/physics_contact_angular_friction.h"
NATIVE = ROOT / "tests/servers/test_godot_physics_contact_angular_friction.cpp"


def angular_impulse(relative_speed, inverse_inertia, normal_load, coefficient, radius):
    if not all(math.isfinite(x) for x in
               (relative_speed, inverse_inertia, normal_load, coefficient, radius)):
        return 0.0
    if inverse_inertia <= 0 or normal_load <= 0 or coefficient <= 0 or radius <= 0:
        return 0.0
    limit = normal_load * coefficient * radius
    if not math.isfinite(limit) or limit <= 0:
        return 0.0
    desired = -relative_speed / inverse_inertia
    if not math.isfinite(desired):
        return 0.0
    return max(-limit, min(desired, limit))


class AngularContactFrictionContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.helper = HELPER.read_text(encoding="utf-8")
        cls.native = NATIVE.read_text(encoding="utf-8")
        cls.pair = {}
        for dimension in ("2d", "3d"):
            path = ROOT / "modules" / f"godot_physics_{dimension}" / f"godot_body_pair_{dimension}.cpp"
            source = path.read_text(encoding="utf-8")
            name = f"GodotBodyPair{dimension.upper()}".replace("2D", "2D").replace("3D", "3D")
            a = source.index(f"bool {name}::pre_solve(")
            b = source.index(f"void {name}::solve(", a)
            cls.pair[dimension] = source[a:b]

    def test_configured_but_disabled_by_default(self):
        for dim in ("2d", "3d"):
            with self.subTest(dim=dim):
                server = (ROOT / "servers" / f"physics_{dim}" / f"physics_server_{dim}.cpp").read_text(encoding="utf-8")
                space_h = (ROOT / "modules" / f"godot_physics_{dim}" / f"godot_space_{dim}.h").read_text(encoding="utf-8")
                space_c = (ROOT / "modules" / f"godot_physics_{dim}" / f"godot_space_{dim}.cpp").read_text(encoding="utf-8")
                self.assertIn(f'"physics/{dim}/solver/rolling_friction", PROPERTY_HINT_RANGE', server)
                self.assertIn(f'GLOBAL_GET("physics/{dim}/solver/rolling_friction")', space_c)
                self.assertIn("real_t rolling_friction = 0.0;", space_h)
                self.assertIn("get_rolling_friction() const", space_h)
                if dim == "3d":
                    self.assertIn('"physics/3d/solver/spinning_friction", PROPERTY_HINT_RANGE', server)
                    self.assertIn('GLOBAL_GET("physics/3d/solver/spinning_friction")', space_c)
                    self.assertIn("real_t spinning_friction = 0.0;", space_h)

    def test_only_loaded_manifold_receives_correction(self):
        for dim, source in self.pair.items():
            with self.subTest(dim=dim):
                self.assertIn("if (!c.active || c.acc_normal_impulse <= 0.0)", source)
                self.assertIn("normal_load_impulse += c.acc_normal_impulse;", source)
                self.assertIn("GodotPhysicsContactAngularFriction::clamped_impulse(", source)
                self.assertIn("if (do_process &&", source)
                self.assertIn("return do_process;", source)

    def test_torque_is_equal_and_opposite(self):
        pair2 = self.pair["2d"]
        pair3 = self.pair["3d"]
        self.assertIn("A->apply_torque_impulse(-torque_impulse);", pair2)
        self.assertIn("B->apply_torque_impulse(torque_impulse);", pair2)
        for body in ("A", "B"):
            self.assertIn(f"{body}->apply_torque_impulse(", pair3)
        self.assertIn("A->apply_torque_impulse(-torque);", pair3)
        self.assertIn("B->apply_torque_impulse(torque);", pair3)

    def test_one_correction_per_step_not_per_solver_iteration(self):
        for dim, source in self.pair.items():
            with self.subTest(dim=dim):
                self.assertIn("space->get_rolling_friction();", source)
                self.assertEqual(source.count("GodotPhysicsContactAngularFriction::clamped_impulse("),
                                 1 if dim == "2d" else 2)
                self.assertNotIn("acc_rolling_impulse", source)
        self.assertIn("once per physics step", self.helper)

    def test_3d_avoids_spurious_mixed_normal_torque(self):
        source = self.pair["3d"]
        self.assertIn("contact_normal.dot(c.normal) < real_t(0.98)", source)
        self.assertIn("normals_compatible = false;", source)
        self.assertIn("have_normal && normals_compatible && normal_load_impulse > 0.0", source)
        self.assertIn("relative_omega - contact_normal * relative_omega.dot(contact_normal)", source)
        self.assertIn("inv_inertia_tensor_A.xform(axis) + inv_inertia_tensor_B.xform(axis)", source)

    def test_helper_degenerate_parameters_return_zero(self):
        for params in [
            (5, 2, 0, .5, 1),
            (5, 0, 2, .5, 1),
            (5, -2, 2, .5, 1),
            (5, 2, 2, 0, 1),
            (5, 2, 2, .5, 0),
            (float("nan"), 2, 2, .5, 1),
            (5, float("inf"), 2, .5, 1),
        ]:
            with self.subTest(params=params):
                self.assertEqual(angular_impulse(*params), 0.0)

    def test_reference_projection_never_increases_relative_angular_speed(self):
        random = __import__("random").Random(90118)
        for _ in range(5000):
            speed = random.uniform(-100, 100)
            inv_inertia = math.exp(random.uniform(-6, 4))
            normal_load = random.uniform(0.00001, 1000)
            coefficient = random.uniform(0, 2)
            radius = random.uniform(0.01, 50)
            impulse = angular_impulse(speed, inv_inertia, normal_load, coefficient, radius)
            corrected_speed = speed + inv_inertia * impulse
            self.assertLessEqual(abs(corrected_speed), abs(speed) + 1e-11)
            self.assertLessEqual(abs(impulse), normal_load * coefficient * radius + 1e-11)

    def test_native_regression_exists(self):
        self.assertIn('TEST_CASE("[GodotPhysics] Friction torque is bounded', self.native)
        self.assertIn('TEST_CASE("[GodotPhysics] Pure angular impulse cannot increase', self.native)


if __name__ == "__main__":
    unittest.main()
