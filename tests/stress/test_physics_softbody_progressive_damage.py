"""Independent numerical and source-integration tests for progressive XPBD damage."""

from __future__ import annotations

import math
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


def advance_damage(length, rest, damage, yield_strain, failure_strain, rate, dt):
    """Python reference, independent of engine/C++ types and code."""
    if rate == 0 or dt == 0:
        return damage
    engineering_strain = length / rest - 1
    load = max(0, min(1, (engineering_strain - yield_strain) / (failure_strain - yield_strain)))
    target = 0.95 * load
    if target <= damage:
        return damage
    fraction = -math.expm1(-rate * dt)
    return damage + (target - damage) * fraction


def alpha_with_damage(base, damage):
    return base / (1 - damage)


class ProgressiveDamageTests(unittest.TestCase):
    def test_unstrained_compressed_and_subyield_links(self):
        for length in [0, 0.5, 1.0, 1.05, 1.09]:
            self.assertEqual(advance_damage(length, 1, 0, 0.1, 0.6, 8, 0.2), 0)

    def test_half_target_and_rate(self):
        # e=0.35, thresholds 0.1..0.6 -> target=0.475.
        value = advance_damage(1.35, 1, 0, 0.1, 0.6, math.log(2), 1)
        self.assertAlmostEqual(value, 0.2375)

    def test_damage_is_monotonic_under_unloading(self):
        value = 0
        for length in [2, 2, 2, 1, 0.5, 1.4, 1, 2]:
            updated = advance_damage(length, 1, value, 0.1, 0.6, 2, .01)
            self.assertGreaterEqual(updated, value)
            self.assertLessEqual(updated, .95)
            value = updated
        self.assertGreater(value, 0)

    def test_full_load_saturates_and_never_fully_disconnects(self):
        value = 0
        for _ in range(100):
            value = advance_damage(10, 1, value, 0.1, 0.6, 20, 1/60)
        self.assertGreater(value, .9)
        self.assertLessEqual(value, .95)
        self.assertLessEqual(alpha_with_damage(.1, value), 2.00000001)

    def test_timestep_independence_constant_load(self):
        one = advance_damage(2, 1, 0, 0.1, 0.6, 3, 1)
        two = 0
        for _ in range(10):
            two = advance_damage(2, 1, two, 0.1, 0.6, 3, 0.1)
        self.assertAlmostEqual(one, two, places=12)

    def test_damage_changes_compliance_not_rest_geometry(self):
        alpha = 0.1
        self.assertEqual(alpha_with_damage(alpha, 0), alpha)
        self.assertAlmostEqual(alpha_with_damage(alpha, 0.5), 0.2)
        self.assertAlmostEqual(alpha_with_damage(alpha, 0.95), 2.0)
        # Effective spring stiffness is proportional to 1/alpha.
        self.assertAlmostEqual((1 / alpha_with_damage(alpha, 0.5)) / (1/alpha), .5)

    def test_settings_default_off_and_cache(self):
        settings = (ROOT / "servers/physics_3d/physics_server_3d.cpp").read_text()
        h = (ROOT / "modules/godot_physics_3d/godot_space_3d.h").read_text()
        cpp = (ROOT / "modules/godot_physics_3d/godot_space_3d.cpp").read_text()
        for key, value in (
            ("soft_body_xpbd_damage_rate", 0.0),
            ("soft_body_xpbd_damage_yield_strain", 0.15),
            ("soft_body_xpbd_damage_failure_strain", 0.55),
        ):
            self.assertIn(f'"physics/3d/solver/{key}"', settings)
            self.assertIn(f"{key} = {value}", h)
            self.assertIn(f'GLOBAL_GET("physics/3d/solver/{key}")', cpp)
            self.assertIn(f"get_{key}()", h)
        self.assertIn("Math::is_finite(configured_damage_rate)", cpp)

    def test_single_persistent_float_and_existing_alpha_scratch(self):
        h = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.h").read_text()
        cpp = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.cpp").read_text()
        self.assertIn("LocalVector<real_t> xpbd_link_damage;", h)
        self.assertIn("use_nonlinear_links = use_tension_hardening || use_damage;", cpp)
        self.assertIn("use_xpbd && damage_rate > 0.0 && damage_failure > damage_yield", cpp)
        self.assertIn("xpbd_link_damage.size() != links.size()", cpp)
        self.assertIn("xpbd_link_damage.resize(links.size())", cpp)
        self.assertIn("xpbd_link_damage.reset();", cpp)
        self.assertIn("physics_softbody_progressive_tension_damage(", cpp)
        self.assertIn("physics_softbody_progressive_damage_alpha(", cpp)
        self.assertIn("xpbd_link_hardening_alphas[link_index] = link_alpha;", cpp)
        self.assertIn("use_nonlinear_links ? xpbd_link_hardening_alphas[link_index] : alpha", cpp)
        self.assertLess(cpp.index("physics_softbody_progressive_tension_damage("),
                        cpp.index("for (int isolve = 0; isolve < iteration_count; ++isolve)"))

    def test_numerical_guards_and_helper_allocation_free(self):
        helper = (ROOT / "servers/physics_softbody_progressive_damage.h").read_text()
        for token in (
            "Math::is_finite(p_rest_length)",
            "Math::is_finite(p_damage_rate)",
            "Math::is_finite(r_damage)",
            "MAX_DAMAGE = 0.95",
            "p_failure_strain > p_yield_strain",
            "if (!(target > double(r_damage)))",
            "const double step_exponent",
            "std::numeric_limits<real_t>::max()",
        ):
            self.assertIn(token, helper)
        self.assertNotIn("memnew(", helper)
        self.assertNotIn("malloc(", helper)

    def test_native_cases_exist(self):
        native = (ROOT / "tests/servers/test_physics_softbody_progressive_damage.cpp").read_text()
        self.assertIn("TEST_FORCE_LINK(test_physics_softbody_progressive_damage)", native)
        self.assertGreaterEqual(native.count("TEST_CASE("), 13)
        self.assertIn("Actual XPBD solver weakens damaged links", native)
        self.assertIn("Damage composes with nonlinear tensile hardening", native)


if __name__ == "__main__":
    unittest.main()
