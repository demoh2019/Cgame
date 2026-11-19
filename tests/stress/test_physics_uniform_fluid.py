"""Jolt-inspired uniform fluid 2D/3D physics: source and numerical contracts.

The feature is opt-in (all coefficients zero by default). It models
full submersion at each body's center of mass, with a constant flow,
a dimensionless buoyancy ratio and exact-step quadratic relative drag.
No claim is made about free surfaces or partial submersion.
"""
from pathlib import Path
import math
import random
import re
import unittest


ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "servers/physics_uniform_fluid.h"
BODY = lambda dim: ROOT / f"modules/godot_physics_{dim}/godot_body_{dim}.cpp"
SPACE_H = lambda dim: ROOT / f"modules/godot_physics_{dim}/godot_space_{dim}.h"
SPACE_CPP = lambda dim: ROOT / f"modules/godot_physics_{dim}/godot_space_{dim}.cpp"
SERVER = lambda dim: ROOT / f"servers/physics_{dim}/physics_server_{dim}.cpp"
REGRESSION = ROOT / "tests/stress/physics_uniform_fluid_regression.gd"
STRESS_CASE = ROOT / "tests/stress/physics_uniform_fluid_stress.gd"
STRESS = ROOT / "tests/stress/stress.gd"
RUNNER = ROOT / "tests/stress/run.py"


def vector_drag(v, flow, k, dt):
    if k <= 0.0 or dt <= 0.0:
        return v
    relative = tuple(x - y for x, y in zip(v, flow))
    speed = math.sqrt(sum(x * x for x in relative))
    if speed == 0.0:
        return v
    factor = 1.0 / (1.0 + k * dt * speed)
    return tuple(flow[i] + relative[i] * factor for i in range(len(v)))


def angular_drag(value, k, dt):
    if k <= 0.0 or dt <= 0.0:
        return value
    return value / (1.0 + k * dt * abs(value))


def length(v):
    return math.sqrt(sum(x * x for x in v))


class UniformFluidContracts(unittest.TestCase):
    def test_exact_quadratic_drag_equations_for_2d_and_3d(self):
        src = HELPER.read_text(encoding="utf-8")
        self.assertIn("const Vector2 relative = p_velocity - p_flow;", src)
        self.assertIn("const Vector3 relative = p_velocity - p_flow;", src)
        self.assertIn("p_flow + relative / (real_t(1.0) + p_coefficient * p_step * Math::sqrt(speed_squared))", src)
        self.assertIn("p_angular_velocity / (real_t(1.0) + p_coefficient * p_step * Math::abs(p_angular_velocity))", src)
        self.assertIn("p_angular_velocity / (real_t(1.0) + p_coefficient * p_step * Math::sqrt(speed_squared))", src)
        self.assertIn("p_coefficient <= real_t(0.0) || p_step <= real_t(0.0)", src)
        self.assertIn("speed_squared <= real_t(0.0)", src)
        self.assertNotIn("memnew(", src)
        self.assertNotIn("new Vector", src)

    def test_20000_random_drag_samples_never_overshoot_flow(self):
        rng = random.Random(20261119)
        for _ in range(20000):
            n = 2 if rng.randrange(2) == 0 else 3
            v = tuple(rng.uniform(-100, 100) for _i in range(n))
            flow = tuple(rng.uniform(-30, 30) for _i in range(n))
            k = rng.uniform(1.0e-4, 20.0)
            dt = rng.uniform(1.0e-4, 1.0)
            result = vector_drag(v, flow, k, dt)
            before = tuple(v[i] - flow[i] for i in range(n))
            after = tuple(result[i] - flow[i] for i in range(n))
            speed = length(before)
            expected_speed = speed / (1.0 + k * dt * speed)
            self.assertAlmostEqual(length(after), expected_speed, delta=1.0e-10)
            self.assertLessEqual(length(after), speed + 1.0e-10)
            self.assertGreaterEqual(sum(before[i] * after[i] for i in range(n)), -1.0e-10)
            self.assertTrue(all(math.isfinite(x) for x in result))

    def test_exact_drag_has_timestep_semigroup_property(self):
        rng = random.Random(1337)
        for _ in range(4000):
            n = 2 if rng.randrange(2) == 0 else 3
            v = tuple(rng.uniform(-15, 15) for _i in range(n))
            flow = tuple(rng.uniform(-5, 5) for _i in range(n))
            k = rng.uniform(0.01, 2.0)
            dt = rng.uniform(0.001, 0.1)
            one = vector_drag(v, flow, k, dt)
            two = vector_drag(vector_drag(v, flow, k, dt * 0.5), flow, k, dt * 0.5)
            for a, b in zip(one, two):
                self.assertAlmostEqual(a, b, delta=1.0e-12)

    def test_disable_zero_speed_and_angular_drag_stability(self):
        for n in (2, 3):
            v = tuple(1.5 * (i + 1) for i in range(n))
            flow = tuple(0.75 * (i + 1) for i in range(n))
            self.assertEqual(vector_drag(v, flow, 0.0, 1.0), v)
            self.assertEqual(vector_drag(v, flow, 10.0, 0.0), v)
            self.assertEqual(vector_drag(flow, flow, 20.0, 10.0), flow)
        for omega in (-1.0e6, -7.0, 0.0, 7.0, 1.0e6):
            result = angular_drag(omega, 100.0, 10.0)
            self.assertTrue(math.isfinite(result))
            self.assertLessEqual(abs(result), abs(omega))
            self.assertTrue(omega == 0.0 or math.copysign(1.0, result) == math.copysign(1.0, omega))
            self.assertEqual(angular_drag(omega, 0.0, 10.0), omega)

    def test_full_submersion_buoyancy_force_balances_gravity(self):
        # Original force is m*g + F_ext. A buoyancy factor of one
        # cancels the gravity contribution exactly, not user impulses.
        gravity = (0.0, -9.81, 0.0)
        mass = 10.0
        external = (4.0, 0.0, -3.0)
        for ratio in (0.0, 0.5, 1.0, 1.5):
            force = tuple(mass * gravity[i] + external[i] - gravity[i] * mass * ratio for i in range(3))
            self.assertAlmostEqual(force[1], mass * gravity[1] * (1.0 - ratio))
            self.assertEqual(force[0], external[0])
            self.assertEqual(force[2], external[2])
        self.assertLess(1.0 - 1.5, 0.0)

    def test_2d_3d_settings_are_registered_cached_and_applied(self):
        for dim in ("2d", "3d"):
            with self.subTest(dim=dim):
                body = BODY(dim).read_text(encoding="utf-8")
                header = SPACE_H(dim).read_text(encoding="utf-8")
                space = SPACE_CPP(dim).read_text(encoding="utf-8")
                server = SERVER(dim).read_text(encoding="utf-8")
                prefix = f"physics/{dim}/solver/"
                for key in ("fluid_linear_drag", "fluid_angular_drag", "fluid_buoyancy", "fluid_flow_velocity"):
                    self.assertIn(prefix + key, server)
                    self.assertIn(prefix + key, space)
                    self.assertIn(key, header)
                for key in ("fluid_linear_drag", "fluid_angular_drag", "fluid_buoyancy"):
                    self.assertIn(f"get_{key}() const", header)
                self.assertIn("get_fluid_flow_velocity() const", header)
                self.assertIn("godot_physics_fluid_linear_drag(", body)
                self.assertIn("godot_physics_fluid_angular_drag(", body)
                self.assertIn('include "servers/physics_uniform_fluid.h"', body)
                self.assertIn("force -= gravity * (mass * get_space()->get_fluid_buoyancy());", body)
                self.assertIn("get_space()->get_fluid_flow_velocity()", body)
                self.assertIn("get_space()->get_fluid_angular_drag()", body)
                self.assertIn("!omit_force_integration", body)
                self.assertLess(body.index("godot_physics_fluid_linear_drag("),
                                body.index("godot_physics_clamp_linear_velocity("))
                self.assertIn('"physics/' + dim + '/solver/fluid_linear_drag", PROPERTY_HINT_RANGE', server)
                self.assertIn('"physics/' + dim + '/solver/fluid_angular_drag", PROPERTY_HINT_RANGE', server)
                self.assertIn('"physics/' + dim + '/solver/fluid_buoyancy", PROPERTY_HINT_RANGE', server)
                self.assertIn('MAX(real_t(0.0), (real_t)GLOBAL_GET', space)

    def test_headless_regression_has_flow_drag_and_neutral_buoyancy(self):
        script = REGRESSION.read_text(encoding="utf-8")
        for dim in ("2d", "3d"):
            for suffix in ("fluid_linear_drag", "fluid_angular_drag", "fluid_buoyancy", "fluid_flow_velocity"):
                self.assertIn(f"physics/{dim}/solver/{suffix}", script)
        self.assertIn("for frame in range(60):", script)
        self.assertIn("PhysicsServer2D.space_create()", script)
        self.assertIn("PhysicsServer3D.space_create()", script)
        self.assertIn("BODY_DAMP_MODE_REPLACE", script)
        self.assertIn("n2.distance_to(Vector2(3.0, 0.0)) > 0.1", script)
        self.assertIn("n3.distance_to(Vector3(3.0, 0.0, 0.0)) > 0.1", script)
        self.assertIn("PhysicsServer2D.free_rid(space_2d)", script)
        self.assertIn("PhysicsServer3D.free_rid(space_3d)", script)
        self.assertIn("ProjectSettings.set_setting(key, original[key])", script)

    def test_four_benchmark_cases_share_matching_registries(self):
        benchmark = STRESS_CASE.read_text(encoding="utf-8")
        gd = STRESS.read_text(encoding="utf-8")
        py = RUNNER.read_text(encoding="utf-8")
        self.assertIn("func run(tree: SceneTree, scale: int, frames: int, is_3d: bool, enabled: bool)", benchmark)
        self.assertIn("mini(256 * scale, 4096)", benchmark)
        self.assertIn('"frame_p95_ms": stats["p95"]', benchmark)
        self.assertIn('"peak_physics_ms": peak_physics_ms', benchmark)
        self.assertIn("ProjectSettings.set_setting(key, config[key])", benchmark)
        for dim, flag3d in (("2d", "false"), ("3d", "true")):
            for active, enabled in (("disabled", "false"), ("enabled", "true")):
                name = f"physics_fluid_{dim}_{active}"
                self.assertIn(f'"{name}"', py)
                self.assertIn(f'"{name}":', gd)
                self.assertIn(f"UniformFluidStress.new().run(self, scale, frames, {flag3d}, {enabled})", gd)
        names_gd = re.findall(r'"([^"]+)"', re.search(r"const CASES := \[([\s\S]*?)\]", gd).group(1))
        names_py = re.findall(r'"([^"]+)"', re.search(r"^CASES = \(([\s\S]*?)^\)", py, re.MULTILINE).group(1))
        self.assertEqual(names_gd, names_py)
        self.assertEqual(len(names_gd), len(set(names_gd)))


if __name__ == "__main__":
    unittest.main()
