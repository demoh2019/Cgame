"""Combined Jolt volumetric topology and orthotropic XPBD reference tests.

Independent source/math checks, not proof of native simulation correctness.
Runs: python3 -m unittest tests/stress/test_jolt_softbody_combined.py -v
"""

import math
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SOFT = ROOT / "modules/jolt_physics/objects/jolt_soft_body_3d.cpp"
SETTINGS = ROOT / "modules/jolt_physics/jolt_project_settings.cpp"
HEADER = ROOT / "modules/jolt_physics/jolt_project_settings.h"
JOLT = ROOT / "thirdparty/jolt_physics/Jolt/Physics/SoftBody/SoftBodySharedSettings.cpp"
PROJECT = ROOT / "tests/stress/jolt_combined/project.godot"
FIXTURE = ROOT / "tests/stress/jolt_combined/combined_softbody_regression.gd"


def directional_compliance(base, offset, axis, ratio):
    """Isotropic = 0; axis 1/2/3 = local X/Y/Z."""
    length_sq = sum(v * v for v in offset)
    if not length_sq or axis == 0 or ratio == 1.0:
        return base
    alignment_sq = offset[axis - 1] ** 2 / length_sq
    return base * (1 + (ratio - 1) * alignment_sq)


class CombinedJoltConstraints(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.code = SOFT.read_text(encoding="utf-8")
        cls.settings = SETTINGS.read_text(encoding="utf-8")
        cls.header = HEADER.read_text(encoding="utf-8")
        cls.jolt = JOLT.read_text(encoding="utf-8")
        cls.generator = cls.code.split(
            "JPH::SoftBodySharedSettings *JoltSoftBody3D::_create_shared_settings() {", 1
        )[1].split("void JoltSoftBody3D::_apply_environmental_forces(", 1)[0]
        cls.builder = cls.code.split("static bool try_build_convex_volume_fan(", 1)[1].split(
            "static void append_volume_radial_springs(", 1
        )[0]
        cls.radial = cls.code.split("static void append_volume_radial_springs(", 1)[1].split(
            "template <typename TJoltVertex>", 1
        )[0]

    def test_jolt_volume_before_lra_cache_allocation(self):
        # Jolt's CreateConstraints computes mClosestKinematic when LRA is on,
        # and Optimize assumes the cached array includes every vertex.
        self.assertIn("if (!mClosestKinematic.empty())", self.jolt)
        self.assertIn("mClosestKinematic.resize(mVertices.size())", self.jolt)
        self.assertLess(
            self.generator.index("try_build_convex_volume_fan(*settings"),
            self.generator.index("settings->CreateConstraints(&vertex_attrib, 1, bend_type)"),
        )
        self.assertLess(
            self.generator.index("try_build_convex_volume_fan(*settings"),
            self.generator.index("const double w1_plus_w2 ="),
        )
        self.assertLess(
            self.generator.index("settings->CreateConstraints(&vertex_attrib, 1, bend_type)"),
            self.generator.index("append_volume_radial_springs(*settings"),
        )
        self.assertLess(
            self.generator.index("append_volume_radial_springs(*settings"),
            self.generator.index("settings->Optimize()"),
        )

    def test_volume_constraint_orientation_matches_signed_jolt_gradient(self):
        self.assertIn("signed_six_volume", self.builder)
        self.assertIn("if (signed_six_volume > 0.0f)", self.builder)
        self.assertIn("face.mVertex[2], face.mVertex[1], center_index", self.builder)
        # Solver compares the absolute volume with rest but uses signed derivatives.
        vendor = (ROOT / "thirdparty/jolt_physics/Jolt/Physics/SoftBody/SoftBodyMotionProperties.cpp").read_text(encoding="utf-8")
        self.assertIn("float c = abs(x1x2.Cross(x1x3).Dot(x1x4))", vendor)

    def test_lra_center_excluded_from_face_graph(self):
        self.assertIn("const uint32_t center_index = (uint32_t)vertices.size();", self.builder)
        self.assertIn("vertices.emplace_back(", self.builder)
        self.assertIn("mVolumeConstraints.emplace_back(", self.builder)
        self.assertIn("if (has_convex_volume && JoltProjectSettings::soft_body_volume_radial_springs)", self.generator)
        self.assertIn("r_settings.mEdgeConstraints.push_back(radial);", self.radial)

    def test_no_topology_mutation_for_invalid_or_disabled_volume(self):
        self.assertIn("soft_body_volume_preservation = false", self.header)
        self.assertIn("if (JoltProjectSettings::soft_body_volume_preservation)", self.generator)
        self.assertLess(self.builder.index("state == nullptr || *state != 0"),
                        self.builder.index("vertices.emplace_back("))
        self.assertIn("if (has_convex_volume && JoltProjectSettings::soft_body_volume_radial_springs)", self.generator)

    def test_directional_defaults_and_finite_clamps(self):
        self.assertIn("soft_body_radial_anisotropy_axis = 0;", self.header)
        self.assertIn("soft_body_radial_anisotropy_ratio = 1.0f;", self.header)
        self.assertIn("Math::is_finite(anisotropy_ratio)", self.settings)
        self.assertIn("CLAMP(anisotropy_ratio, 0.1f, 10.0f)", self.settings)
        self.assertIn("CLAMP((int)GLOBAL_GET(\"physics/jolt_physics_3d/simulation/soft_body_radial_anisotropy_axis\"), 0, 3)", self.settings)

    def test_axial_compliance_is_correct_and_isotropic_by_default(self):
        base = 0.001
        for offset in [(1, 0, 0), (0, 1, 0), (0, 0, 1), (1, 1, 0)]:
            self.assertAlmostEqual(directional_compliance(base, offset, 0, 4.0), base)
            self.assertAlmostEqual(directional_compliance(base, offset, 1, 1.0), base)
        self.assertAlmostEqual(directional_compliance(base, (3, 0, 0), 1, 4.0), 4 * base)
        self.assertAlmostEqual(directional_compliance(base, (0, 3, 0), 1, 4.0), base)
        self.assertAlmostEqual(directional_compliance(base, (3, 4, 0), 1, 4.0),
                               base * (1 + 3 * 9 / 25))
        self.assertAlmostEqual(directional_compliance(base, (0, 0, 1), 3, 0.1), base * 0.1)
        self.assertAlmostEqual(directional_compliance(base, (1, 0, 0), 3, 0.1), base)

    def test_weight_is_normalized_and_bounded(self):
        self.assertIn("(axis_displacement * axis_displacement) / distance_sq", self.radial)
        self.assertIn("1.0f + (p_anisotropy_ratio - 1.0f) * alignment_sq", self.radial)
        for ratio in (0.1, 0.3, 1.0, 4.0, 10.0):
            for direction in ((1, 0, 0), (0, 1, 0), (0, 0, 1), (1, 2, 3)):
                value = directional_compliance(0.01, direction, 2, ratio)
                self.assertTrue(math.isfinite(value))
                self.assertGreaterEqual(value, 0.01 * min(1, ratio) - 1e-12)
                self.assertLessEqual(value, 0.01 * max(1, ratio) + 1e-12)

    def test_project_runs_combined_features_on_same_body(self):
        cfg = PROJECT.read_text(encoding="utf-8")
        scene = FIXTURE.read_text(encoding="utf-8")
        for setting in (
            "soft_body_lra_mode=2",
            "soft_body_bend_mode=2",
            "soft_body_volume_preservation=true",
            "soft_body_volume_radial_springs=true",
            "soft_body_radial_anisotropy_axis=2",
            "soft_body_radial_anisotropy_ratio=4.0",
        ):
            self.assertIn(setting, cfg)
        self.assertIn("PASS: combined Jolt volume, LRA, bending and directional radial elasticity", scene)


if __name__ == "__main__":
    unittest.main()
