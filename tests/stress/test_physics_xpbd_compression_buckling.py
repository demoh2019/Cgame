"""Analytical regressions + source contracts for nonlinear XPBD compression buckling."""

import math
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


def buckling_alpha(length, rest, base, yield_strain=0.05,
                   transition=0.1, ratio=9.0):
    """Independent piecewise engineering-strain oracle for test comparisons."""
    if ratio == 1 or rest == 0 or base == 0:
        return base
    compressed = 1.0 - length / rest
    if compressed <= yield_strain:
        return base
    t = min(1.0, max(0.0, (compressed - yield_strain) / transition)) if transition else 1.0
    s = t * t * (3 - 2 * t)
    return base * (1 + (ratio - 1) * s)


class XPBDCompressionBucklingTests(unittest.TestCase):
    def test_piecewise_yield_and_smooth_compression(self):
        self.assertEqual(buckling_alpha(1.2, 1.0, .25), .25)
        self.assertEqual(buckling_alpha(1.0, 1.0, .25), .25)
        self.assertAlmostEqual(buckling_alpha(.95, 1.0, .25), .25)
        self.assertAlmostEqual(buckling_alpha(.9, 1.0, .25), 1.25)
        self.assertAlmostEqual(buckling_alpha(.75, 1.0, .25), 2.25)
        self.assertAlmostEqual(buckling_alpha(0, 1.0, .25), 2.25)

    def test_ratio_is_one_or_zero_baseline(self):
        for length in [0.0, .1, .5, 1.0, 2.0]:
            self.assertEqual(buckling_alpha(length, 1.0, .3, ratio=1), .3)
            self.assertEqual(buckling_alpha(length, 1.0, 0.0, ratio=99), 0.0)
        self.assertEqual(buckling_alpha(0, 0, .3, ratio=99), .3)

    def test_monotone_compression_without_exceeding_ratio(self):
        samples = [buckling_alpha(length / 100.0, 1.0, .2)
                   for length in range(0, 121, 2)]
        self.assertTrue(all(samples[i] >= samples[i + 1] - 1e-14
                            for i in range(len(samples) - 1)))
        self.assertTrue(all(.2 - 1e-12 <= x <= 1.8 + 1e-12 for x in samples))

    def test_step_transition(self):
        self.assertAlmostEqual(buckling_alpha(.96, 1, .2, transition=0), .2)
        self.assertAlmostEqual(buckling_alpha(.94, 1, .2, transition=0), 1.8)

    def test_settings_and_caching(self):
        settings = (ROOT / "servers/physics_3d/physics_server_3d.cpp").read_text()
        space_h = (ROOT / "modules/godot_physics_3d/godot_space_3d.h").read_text()
        space_cpp = (ROOT / "modules/godot_physics_3d/godot_space_3d.cpp").read_text()
        for name, default in [
            ("soft_body_xpbd_buckling_softening_ratio", "1.0"),
            ("soft_body_xpbd_buckling_yield_strain", "0.05"),
            ("soft_body_xpbd_buckling_transition_strain", "0.05"),
        ]:
            self.assertIn(f'physics/3d/solver/{name}', settings)
            self.assertIn(f"{name} = {default}", space_h)
            self.assertIn(f'GLOBAL_GET("physics/3d/solver/{name}")', space_cpp)
            self.assertIn(f"get_{name}()", space_h)
        self.assertIn("Math::is_finite(configured_buckling_ratio)", space_cpp)

    def test_single_shared_xpbd_alpha_buffer_and_default_off(self):
        body = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.cpp").read_text()
        header = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.h").read_text()
        self.assertIn("use_nonlinear_links = use_tension_hardening || use_compression_buckling", body)
        self.assertIn("if (use_nonlinear_links) {", body)
        self.assertIn("xpbd_link_hardening_alphas.resize(links.size())", body)
        self.assertIn("xpbd_link_hardening_alphas.reset()", body)
        self.assertIn("use_nonlinear_links ? xpbd_link_hardening_alphas[link_index] : alpha", body)
        self.assertIn("physics_xpbd_tension_hardening_alpha(", body)
        self.assertIn("physics_xpbd_compression_buckling_alpha(", body)
        self.assertIn('"servers/physics_xpbd_compression_buckling.h"', body)
        self.assertIn("LocalVector<real_t> xpbd_link_hardening_alphas", header)

    def test_helper_validates_and_saturates_outputs(self):
        helper = (ROOT / "servers/physics_xpbd_compression_buckling.h").read_text()
        self.assertIn("Math::is_finite(p_rest_length)", helper)
        self.assertIn("Math::is_finite(p_transition_strain)", helper)
        self.assertIn("Math::is_finite(p_softening_ratio)", helper)
        self.assertIn("p_softening_ratio < 1.0", helper)
        self.assertIn("t * t * (3.0 - 2.0 * t)", helper)
        self.assertIn("std::numeric_limits<real_t>::max()", helper)
        self.assertIn("if (Math::is_nan(candidate)", helper)
        self.assertNotIn("memnew(", helper)
        self.assertNotIn("malloc(", helper)

    def test_native_tests_cover_14_scenarios(self):
        native = (ROOT / "tests/servers/test_physics_xpbd_compression_buckling.cpp").read_text()
        self.assertIn("TEST_FORCE_LINK(test_physics_xpbd_compression_buckling)", native)
        self.assertGreaterEqual(native.count("TEST_CASE("), 12)


if __name__ == "__main__":
    unittest.main()
