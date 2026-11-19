"""Source and mathematical contracts for opt-in Box2D-style implicit damping.

These tests do not replace compiling the engine and running
physics_implicit_damping_regression.gd on the GodotPhysics backend.
"""
from pathlib import Path
import math
import random
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "servers/physics_damping.h"
RUNTIME = ROOT / "tests/stress/physics_implicit_damping_regression.gd"
WORKLOAD = ROOT / "tests/stress/physics_implicit_damping_stress.gd"
RUNNER = ROOT / "tests/stress/run.py"
STRESS = ROOT / "tests/stress/stress.gd"


def damping_factor(dt: float, damping: float, implicit: bool) -> float:
    amount = dt * damping
    if implicit and amount > 0.0:
        return 1.0 / (1.0 + amount)
    legacy = 1.0 - amount
    return 0.0 if legacy < 0.0 else legacy


class ImplicitDampingContracts(unittest.TestCase):
    def test_legacy_and_implicit_factor_both_math_stable(self):
        rng = random.Random(20261119)
        for _ in range(2000):
            dt = rng.uniform(0.0001, 0.1)
            c = rng.uniform(0.0, 1000.0)
            amount = dt * c
            legacy = damping_factor(dt, c, False)
            implicit = damping_factor(dt, c, True)
            self.assertEqual(legacy, max(0.0, 1.0 - amount))
            self.assertAlmostEqual(implicit, 1.0 / (1.0 + amount), places=14)
            self.assertTrue(0.0 < implicit <= 1.0)
            if amount >= 1.0:
                self.assertEqual(legacy, 0.0)
                self.assertGreater(implicit, 0.0)
        self.assertEqual(damping_factor(0.0, 120.0, True), 1.0)
        self.assertEqual(damping_factor(0.1, 0.0, True), 1.0)
        # Negative damping remains the legacy amplification path.
        self.assertEqual(damping_factor(0.1, -2.0, True), 1.2)
        self.assertEqual(damping_factor(0.1, -2.0, False), 1.2)

    def test_shared_helper_preserves_exact_legacy_branch(self):
        source = HELPER.read_text(encoding="utf-8")
        self.assertIn("godot_physics_damping_factor(real_t p_step, real_t p_damping, bool p_implicit)", source)
        self.assertIn("const real_t attenuation = p_step * p_damping;", source)
        self.assertIn("if (p_implicit && attenuation > real_t(0.0))", source)
        self.assertIn("return real_t(1.0) / (real_t(1.0) + attenuation);", source)
        self.assertIn("const real_t legacy_factor = real_t(1.0) - attenuation;", source)
        self.assertIn("legacy_factor < real_t(0.0) ? real_t(0.0) : legacy_factor", source)

    def test_defaults_are_false_and_spaces_cache_option_once(self):
        for dim in ("2d", "3d"):
            with self.subTest(dimension=dim):
                settings = (ROOT / f"servers/physics_{dim}/physics_server_{dim}.cpp").read_text()
                space_h = (ROOT / f"modules/godot_physics_{dim}/godot_space_{dim}.h").read_text()
                space_cpp = (ROOT / f"modules/godot_physics_{dim}/godot_space_{dim}.cpp").read_text()
                setting = f"physics/{dim}/solver/implicit_damping"
                self.assertIn(f'GLOBAL_DEF(PropertyInfo(Variant::BOOL, "{setting}"), false);', settings)
                self.assertIn("bool implicit_damping = false;", space_h)
                self.assertIn("bool is_implicit_damping_enabled() const", space_h)
                self.assertIn(f'implicit_damping = GLOBAL_GET("{setting}");', space_cpp)

    def test_both_velocity_components_use_shared_helper(self):
        for dim in ("2d", "3d"):
            with self.subTest(dimension=dim):
                source = (ROOT / f"modules/godot_physics_{dim}/godot_body_{dim}.cpp").read_text()
                self.assertIn('#include "servers/physics_damping.h"', source)
                self.assertIn("get_space()->is_implicit_damping_enabled()", source)
                self.assertIn("godot_physics_damping_factor(p_step, total_linear_damp, implicit_damping)", source)
                self.assertIn("godot_physics_damping_factor(p_step, total_angular_damp, implicit_damping)", source)
                self.assertIn("linear_velocity *= damp;", source)
                self.assertIn("angular_velocity *= angular_damp_new;", source)
                self.assertIn("linear_velocity += ", source)
                self.assertIn("angular_velocity += ", source)

    def test_runtime_regression_uses_two_independent_spaces_per_dimension(self):
        code = RUNTIME.read_text(encoding="utf-8")
        self.assertIn("for dimension in [2, 3]:", code)
        self.assertIn("for enabled in [false, true]:", code)
        self.assertIn("120.0", code)
        self.assertIn("1.0 / (1.0 + 120.0 / 60.0)", code)
        self.assertIn("BODY_DAMP_MODE_REPLACE", code)
        self.assertIn("PhysicsServer2D.space_create()", code)
        self.assertIn("PhysicsServer3D.space_create()", code)
        self.assertIn("ProjectSettings.set_setting(setting, original)", code)
        self.assertIn("Engine.physics_ticks_per_second = saved_ticks", code)
        self.assertIn("await physics_frame", code)

    def test_four_stress_scenarios_exist_and_match_dispatch(self):
        workload = WORKLOAD.read_text(encoding="utf-8")
        stress = STRESS.read_text(encoding="utf-8")
        runner = RUNNER.read_text(encoding="utf-8")
        self.assertIn("func run_2d(", workload)
        self.assertIn("func run_3d(", workload)
        self.assertIn("min\u0069(256 * scale, 4096)", workload)
        self.assertIn("BODY_STATE_CAN_SLEEP, false", workload)
        self.assertIn('"frame_p95_ms": stats["p95"]', workload)
        for dim in ("2d", "3d"):
            for mode, enabled in (("legacy", "false"), ("implicit", "true")):
                case = f"physics_damping_{mode}_{dim}"
                self.assertIn(f'"{case}"', runner)
                self.assertIn(f'"{case}":', stress)
                self.assertIn(
                    f"ImplicitDampingStress.new().run_{dim}(self, scale, frames, {enabled})",
                    stress,
                )
        # Fail when scripts disagree: the runner sends case names verbatim.
        gd_cases = re.search(r"const CASES := \[([\s\S]*?)\]", stress)
        py_cases = re.search(r"^CASES = \(([\s\S]*?)^\)", runner, re.MULTILINE)
        self.assertIsNotNone(gd_cases)
        self.assertIsNotNone(py_cases)
        names_gd = re.findall(r'"([^"]+)"', gd_cases.group(1))
        names_py = re.findall(r'"([^"]+)"', py_cases.group(1))
        self.assertEqual(names_gd, names_py)
        self.assertEqual(len(names_gd), len(set(names_gd)))


if __name__ == "__main__":
    unittest.main()
