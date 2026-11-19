"""Jolt volumetric XPBD contraction: rest-volume scales cubically.

The existing convex tetrahedral volume fan stores 6x signed rest volume.
This regression validates the opt-in material mode: conserving original
volume vs scaling it consistently with the rest lengths of cloth edges.
Native Cgame Jolt solver behavior is covered in a separate GDScript test.
"""

from pathlib import Path
import math
import random
import unittest


ROOT = Path(__file__).resolve().parents[2]
CPP = ROOT / "modules/jolt_physics/objects/jolt_soft_body_3d.cpp"
SETTINGS_H = ROOT / "modules/jolt_physics/jolt_project_settings.h"
SETTINGS_CPP = ROOT / "modules/jolt_physics/jolt_project_settings.cpp"
JOLT_H = ROOT / "thirdparty/jolt_physics/Jolt/Physics/SoftBody/SoftBodySharedSettings.h"
SCRIPT = ROOT / "tests/stress/physics_jolt_softbody_volume_shrink_regression.gd"

FLOAT_MAX = 3.4028234663852886e38


def scaled_six_rest_volume(six_rest_volume, shrink, follow_shrink):
    if not follow_shrink:
        return six_rest_volume
    factor = max(1.0 - shrink, 0.0)
    scale = factor ** 3
    return max(-FLOAT_MAX, min(FLOAT_MAX, six_rest_volume * scale))


def signed_tetra_six_volume(a, b, c, d):
    def sub(u, v):
        return tuple(x - y for x, y in zip(u, v))
    def dot(u, v):
        return sum(x * y for x, y in zip(u, v))
    def cross(u, v):
        return (
            u[1] * v[2] - u[2] * v[1],
            u[2] * v[0] - u[0] * v[2],
            u[0] * v[1] - u[1] * v[0],
        )
    return dot(cross(sub(b, a), sub(c, a)), sub(d, a))


class JoltVolumetricContractionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cpp = CPP.read_text(encoding="utf-8")
        cls.settings_h = SETTINGS_H.read_text(encoding="utf-8")
        cls.settings_cpp = SETTINGS_CPP.read_text(encoding="utf-8")
        cls.jolt_h = JOLT_H.read_text(encoding="utf-8")
        cls.builder = cls.cpp.split(
            "JPH::SoftBodySharedSettings *JoltSoftBody3D::_create_shared_settings() {", 1
        )[1].split("\nvoid JoltSoftBody3D::_apply_environmental_forces(", 1)[0]

    def test_new_material_mode_is_explicitly_opt_in(self):
        self.assertIn("inline static bool soft_body_volume_follow_shrinking_factor = false;", self.settings_h)
        self.assertIn(
            '"physics/jolt_physics_3d/simulation/soft_body_volume_follow_shrinking_factor"), false',
            self.settings_cpp,
        )
        self.assertIn(
            'soft_body_volume_follow_shrinking_factor = GLOBAL_GET('
            '"physics/jolt_physics_3d/simulation/soft_body_volume_follow_shrinking_factor");',
            self.settings_cpp,
        )

    def test_existing_incompressible_volume_setting_unchanged(self):
        self.assertIn("inline static bool soft_body_volume_preservation = false;", self.settings_h)
        self.assertIn("if (JoltProjectSettings::soft_body_volume_preservation)", self.builder)
        self.assertIn("try_build_convex_volume_fan(*settings", self.builder)
        self.assertIn("settings->mVolumeConstraints", self.builder)

    def test_cubic_volume_scale_after_constraint_creation(self):
        code = self.builder
        self.assertIn("const float multiplier = 1.0f - shrinking_factor;", code)
        self.assertIn("e.mRestLength *= multiplier;", code)
        self.assertIn("tether.mMaxDistance *= multiplier;", code)
        self.assertIn("const double scale = double(multiplier);", code)
        self.assertIn("const double volume_scale = scale * scale * scale;", code)
        self.assertIn("volume.mSixRestVolume = float(CLAMP(target, -double(FLT_MAX), double(FLT_MAX)));", code)
        self.assertLess(code.index("settings->CreateConstraints(&vertex_attrib"),
                        code.index("volume.mSixRestVolume ="))
        self.assertLess(code.index("try_build_convex_volume_fan(*settings"),
                        code.index("volume.mSixRestVolume ="))
        self.assertLess(code.index("volume.mSixRestVolume ="),
                        code.index("settings->Optimize();"))

    def test_default_and_zero_shrink_add_no_extra_volume_work(self):
        code = self.builder
        self.assertIn("if (has_volume_fan && JoltProjectSettings::soft_body_volume_follow_shrinking_factor &&", code)
        self.assertIn("multiplier != 1.0f && multiplier > 0.0f)", code)
        self.assertIn("has_volume_fan && JoltProjectSettings::soft_body_volume_follow_shrinking_factor", code)
        self.assertIn("if (Math::is_finite(volume_scale))", code)
        self.assertIn("for (JPH::SoftBodySharedSettings::Volume &volume : settings->mVolumeConstraints)", code)
        self.assertIn("const uint32_t surface_edge_count = (uint32_t)settings->mEdgeConstraints.size();", code)
        self.assertIn("for (uint32_t i = surface_edge_count; i < settings->mEdgeConstraints.size(); ++i)", code)
        self.assertIn("radial.mRestLength = float(MIN(target, double(FLT_MAX)));", code)

    def test_radial_spokes_are_scaled_only_after_convex_fan_creation(self):
        code = self.builder
        self.assertIn("const bool has_volume_fan = try_build_convex_volume_fan(", code)
        self.assertIn("JoltProjectSettings::soft_body_volume_radial_springs", code)
        self.assertIn("const uint32_t surface_edge_count = (uint32_t)settings->mEdgeConstraints.size();", code)
        self.assertIn("radial.mRestLength = float(MIN(target, double(FLT_MAX)));", code)
        self.assertLess(code.index("surface_edge_count ="), code.index("const bool has_volume_fan"))
        self.assertLess(code.index("const bool has_volume_fan"), code.index("radial.mRestLength ="))
        self.assertLess(code.index("radial.mRestLength ="), code.index("settings->Optimize();"))

    def test_volume_scaling_does_not_run_on_invalid_or_open_mesh(self):
        code = self.builder
        self.assertIn("has_volume_fan &&", code)
        self.assertIn("multiplier > 0.0f", code)
        self.assertIn("Math::is_finite(volume_scale)", code)
        self.assertIn("const double target = double(volume.mSixRestVolume) * volume_scale;", code)

    def test_jolt_volume_rest_value_and_constraint_type(self):
        self.assertIn("struct JPH_EXPORT Volume", self.jolt_h)
        self.assertIn("float", self.jolt_h.split("mSixRestVolume = 1.0f", 1)[0][-60:])
        self.assertIn("mSixRestVolume = 1.0f", self.jolt_h)
        self.assertIn("CalculateVolumeConstraintVolumes();", self.cpp)

    def test_signed_volume_preserved_during_shrink_and_expansion(self):
        unit = signed_tetra_six_volume(
            (0, 0, 0), (1, 0, 0), (0, 1, 0), (0, 0, 1)
        )
        self.assertAlmostEqual(abs(unit), 1.0)
        for signed in (unit, -unit):
            self.assertEqual(scaled_six_rest_volume(signed, 0.0, True), signed)
            self.assertAlmostEqual(scaled_six_rest_volume(signed, 0.25, True), signed * 0.75 ** 3)
            self.assertAlmostEqual(scaled_six_rest_volume(signed, -0.2, True), signed * 1.2 ** 3)
            self.assertEqual(scaled_six_rest_volume(signed, 0.25, False), signed)

    def test_20000_randomized_isotropic_volume_scalings(self):
        rng = random.Random(20261119)
        for _ in range(20000):
            rest = rng.uniform(-1000.0, 1000.0)
            shrink = rng.uniform(-0.95, 0.95)
            scale = 1.0 - shrink
            expected = rest * scale ** 3
            actual = scaled_six_rest_volume(rest, shrink, True)
            self.assertTrue(math.isfinite(actual))
            self.assertAlmostEqual(actual, expected, delta=abs(expected) * 1.0e-12 + 1.0e-10)
            self.assertEqual(scaled_six_rest_volume(rest, shrink, False), rest)

    def test_native_fixture_checks_two_modes_and_three_shrinks(self):
        script = SCRIPT.read_text(encoding="utf-8")
        for needle in (
            'const SHRINK_VALUES := [-0.15, 0.0, 0.25]',
            'const FRAMES := 90',
            'soft_body_set_shrinking_factor',
            'soft_body_pin_point',
            'soft_body_get_point_global_position',
            'pow(1.0 - shrink, 3.0) if enabled else rest_volume',
            'JOLT_SOFTBODY_VOLUME_SHRINK_RESULT:',
            'Jolt soft-body volumetric shrink regression passed.',
            'soft_body_volume_radial_springs',
        ):
            self.assertIn(needle, script)


if __name__ == "__main__":
    unittest.main()
