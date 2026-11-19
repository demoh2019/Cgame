"""Source contracts and reference properties for Rapier-style per-step CCD rotation caps.

This opt-in safeguard prevents large per-step angular displacement for CCD
rigid bodies without changing rotation for other bodies. It is not nonlinear
CCD and cannot guarantee prevention of all rotational tunneling.
"""

import math
import random
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "servers/physics_angular_velocity_cap.h"
NATIVE = ROOT / "tests/servers/test_godot_physics_ccd_angular_motion.cpp"
SCENE = ROOT / "tests/stress/physics_ccd_angular_motion_regression.gd"


def clamp_scalar(omega, max_angle, dt):
    if max_angle <= 0 or dt <= 0 or not math.isfinite(max_angle) or not math.isfinite(dt):
        return omega
    speed_limit = max_angle / dt
    if not math.isfinite(speed_limit):
        return omega
    return max(-speed_limit, min(speed_limit, omega))


def clamp_vector(omega, max_angle, dt):
    if max_angle <= 0 or dt <= 0 or not math.isfinite(max_angle) or not math.isfinite(dt):
        return omega
    limit = max_angle / dt
    magnitude = math.hypot(*omega)
    if magnitude <= limit or magnitude == 0 or not math.isfinite(magnitude):
        return omega
    factor = limit / magnitude
    return tuple(v * factor for v in omega)


class CCDAngularMotionContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.helper = HELPER.read_text(encoding="utf-8")
        cls.native = NATIVE.read_text(encoding="utf-8")
        cls.scene = SCENE.read_text(encoding="utf-8")
        cls.pairs = {}
        for dimension in ("2d", "3d"):
            cls.pairs[dimension] = {
                "body": (ROOT / "modules" / f"godot_physics_{dimension}" /
                         f"godot_body_{dimension}.cpp").read_text(encoding="utf-8"),
                "space_h": (ROOT / "modules" / f"godot_physics_{dimension}" /
                            f"godot_space_{dimension}.h").read_text(encoding="utf-8"),
                "space_cpp": (ROOT / "modules" / f"godot_physics_{dimension}" /
                              f"godot_space_{dimension}.cpp").read_text(encoding="utf-8"),
                "server": (ROOT / "servers" / f"physics_{dimension}" /
                           f"physics_server_{dimension}.cpp").read_text(encoding="utf-8"),
            }

    def test_default_0_and_per_space_cached(self):
        for dimension, source in self.pairs.items():
            with self.subTest(dimension=dimension):
                self.assertIn("real_t ccd_max_angular_motion = 0.0;", source["space_h"])
                self.assertIn("get_ccd_max_angular_motion() const", source["space_h"])
                self.assertIn(f'GLOBAL_GET("physics/{dimension}/solver/ccd_max_angular_motion")', source["space_cpp"])
                self.assertIn(f'"physics/{dimension}/solver/ccd_max_angular_motion", PROPERTY_HINT_RANGE', source["server"])
                self.assertIn("0.0);", source["server"])

    def test_2d_and_3d_helper_guards_invalid_steps(self):
        self.assertEqual(self.helper.count("godot_physics_clamp_ccd_angular_velocity("), 2)
        self.assertIn("!(p_step > real_t(0.0)) || !Math::is_finite(p_step)", self.helper)
        self.assertIn("!(p_max_angle > real_t(0.0)) || !Math::is_finite(p_max_angle)", self.helper)
        self.assertIn("const real_t speed_limit = p_max_angle / p_step;", self.helper)
        self.assertIn("!Math::is_finite(speed_limit)", self.helper)

    def test_dynamic_ccd_only_not_kinematic(self):
        for dimension, source in self.pairs.items():
            with self.subTest(dimension=dimension):
                body = source["body"]
                force = body[body.index(f"void GodotBody{dimension.upper()}::integrate_forces("):
                             body.index(f"void GodotBody{dimension.upper()}::integrate_velocities(")]
                velocity = body[body.index(f"void GodotBody{dimension.upper()}::integrate_velocities("):]
                ccd_guard = ("continuous_cd_mode != PS2DE::CCD_MODE_DISABLED"
                             if dimension == "2d" else "continuous_cd")
                self.assertIn(f"if ({ccd_guard})", force)
                self.assertIn(f"if ({ccd_guard})", velocity)
                self.assertEqual(body.count("godot_physics_clamp_ccd_angular_velocity("), 2)
                self.assertLess(force.index("godot_physics_clamp_ccd_angular_velocity("),
                                force.index("if (do_motion)"))
                self.assertLess(velocity.index("if (mode == PS" + dimension.upper() + "::BODY_MODE_KINEMATIC)"),
                                velocity.index("godot_physics_clamp_ccd_angular_velocity("))

    def test_preserves_existing_angular_speed_limit(self):
        for dimension, source in self.pairs.items():
            with self.subTest(dimension=dimension):
                body = source["body"]
                self.assertEqual(body.count("godot_physics_clamp_angular_velocity("), 2)
                self.assertEqual(body.count("godot_physics_clamp_ccd_angular_velocity("), 2)
                self.assertIn("get_space()->get_max_angular_velocity()", body)
                self.assertIn("get_space()->get_ccd_max_angular_motion()", body)

    def test_runtime_covers_both_ccd_states_and_both_dimensions(self):
        self.assertIn("for dimension in [2, 3]:", self.scene)
        self.assertIn("_exercise(dimension, false)", self.scene)
        self.assertIn("_exercise(dimension, true)", self.scene)
        self.assertIn("PhysicsServer2D.CCD_MODE_CAST_SHAPE", self.scene)
        self.assertIn("PhysicsServer3D.body_set_enable_continuous_collision_detection(body, ccd)", self.scene)
        self.assertIn("measured_peak <= speed_cap + 0.01", self.scene)
        self.assertIn("measured_low >= INITIAL_SPEED - 0.1", self.scene)

    def test_native_cases_present(self):
        self.assertEqual(self.native.count("TEST_CASE("), 5)
        self.assertIn("Per-step CCD angular cap scales with delta", self.native)
        self.assertIn("CCD angular cap preserves 3D rotation direction", self.native)

    def test_zero_limit_and_invalid_steps_are_noop(self):
        omega3 = (30.0, -70.0, 90.0)
        for max_angle, step in ((0, 1/60), (-1, 1/60), (math.nan, 1/60),
                                (.8, 0), (.8, -1), (.8, math.inf)):
            self.assertEqual(clamp_scalar(120, max_angle, step), 120)
            self.assertEqual(clamp_vector(omega3, max_angle, step), omega3)

    def test_12000_random_rotation_bounds(self):
        rng = random.Random(20261119)
        for _ in range(12000):
            omega = rng.uniform(-10000, 10000)
            omega3 = tuple(rng.uniform(-10000, 10000) for _ in range(3))
            max_angle = rng.uniform(.01, math.pi)
            step = rng.uniform(1/480, 1/15)
            out = clamp_scalar(omega, max_angle, step)
            vec = clamp_vector(omega3, max_angle, step)
            self.assertLessEqual(abs(out) * step, max_angle + 1e-9)
            self.assertLessEqual(math.hypot(*vec) * step, max_angle + 1e-9)
            self.assertLessEqual(abs(out), abs(omega) + 1e-9)
            self.assertLessEqual(math.hypot(*vec), math.hypot(*omega3) + 1e-9)
            self.assertGreaterEqual(out * omega, 0)
            self.assertGreaterEqual(sum(a*b for a, b in zip(vec, omega3)), -1e-9)


if __name__ == "__main__":
    unittest.main()
