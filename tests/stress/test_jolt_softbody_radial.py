"""Source and mathematical contracts for optional convex soft-body radial springs.

The native scene at tests/stress/jolt_radial/radial_elasticity_regression.gd
is needed to test the solver; this suite is not a physics-engine build.
"""
import math
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "modules/jolt_physics/objects/jolt_soft_body_3d.cpp"
SETTINGS = ROOT / "modules/jolt_physics/jolt_project_settings.cpp"
HEADER = ROOT / "modules/jolt_physics/jolt_project_settings.h"
JOLT = ROOT / "thirdparty/jolt_physics/Jolt/Physics/SoftBody/SoftBodySharedSettings.h"
FIXTURE = ROOT / "tests/stress/jolt_radial/radial_elasticity_regression.gd"
PROJECT = ROOT / "tests/stress/jolt_radial/project.godot"


def fan_spoke_lengths(positions):
    center = tuple(
        math.fsum(p[i] for p in positions) / len(positions)
        for i in range(3)
    )
    return [math.dist(p, center) for p in positions]


class RadialElasticityContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cpp = SOURCE.read_text(encoding="utf-8")
        cls.settings = SETTINGS.read_text(encoding="utf-8")
        cls.header = HEADER.read_text(encoding="utf-8")
        cls.jolt = JOLT.read_text(encoding="utf-8")
        cls.builder = cls.cpp.split("static bool try_build_convex_volume_fan(", 1)[1].split(
            "template <typename TJoltVertex>", 1
        )[0]

    def test_feature_is_disabled_by_default(self):
        self.assertIn("inline static bool soft_body_volume_radial_springs = false;", self.header)
        self.assertIn('simulation/soft_body_volume_radial_springs"), false', self.settings)
        self.assertIn("if (has_convex_volume && JoltProjectSettings::soft_body_volume_radial_springs)", self.cpp)
        self.assertIn("if (JoltProjectSettings::soft_body_volume_preservation)", self.cpp)

    def test_compliance_is_finite_and_nonnegative(self):
        self.assertIn("Math::is_finite(radial_compliance)", self.settings)
        self.assertIn("CLAMP(radial_compliance, 0.0f, 1.0f)", self.settings)
        self.assertIn("soft_body_volume_radial_compliance = 0.0001f", self.header)
        self.assertIn("p_compliance", self.builder)

    def test_constraints_are_real_jolt_edge_constraints(self):
        self.assertIn("JPH::SoftBodySharedSettings::Edge radial(center_index, i, compliance);", self.builder)
        self.assertIn("radial.mRestLength = Math::sqrt(distance_sq);", self.builder)
        self.assertIn("r_settings.mEdgeConstraints.push_back(radial);", self.builder)
        self.assertIn("Edge(uint32 inVertex1, uint32 inVertex2, float inCompliance", self.jolt)

    def test_spoke_generation_happens_after_manifold_validation(self):
        self.assertLess(self.builder.index("state == nullptr || *state != 0"), self.builder.index("vertices.emplace_back("))
        self.assertLess(self.builder.index("CalculateVolumeConstraintVolumes();"), self.builder.index("static void append_volume_radial_springs("))
        self.assertIn("if (distance_sq <= min_distance_sq)", self.builder)

    def test_keep_surface_shrink_separate_from_spoke_rest_length(self):
        self.assertLess(self.cpp.index("try_build_convex_volume_fan(*settings"),
                        self.cpp.index("settings->CreateConstraints(&vertex_attrib, 1, bend_type)"))
        self.assertLess(self.cpp.index("e.mRestLength *= multiplier;"),
                        self.cpp.index("append_volume_radial_springs(*settings"))
        self.assertLess(self.cpp.index("append_volume_radial_springs(*settings"),
                        self.cpp.index("settings->Optimize()"))
        self.assertIn("LRA &tether", self.cpp)

    def test_spoke_geometry_on_tetra_and_cube(self):
        tetra = [(0, 0, 0), (1, 0, 0), (0, 1, 0), (0, 0, 1)]
        cube = [(x, y, z) for x in (-1, 1) for y in (-1, 1) for z in (-1, 1)]
        t_lengths = fan_spoke_lengths(tetra)
        c_lengths = fan_spoke_lengths(cube)
        self.assertEqual(len(t_lengths), 4)
        self.assertEqual(len(c_lengths), 8)
        self.assertAlmostEqual(t_lengths[0], math.sqrt(3) / 4)
        self.assertAlmostEqual(t_lengths[1], math.sqrt(11) / 4)
        for length in c_lengths:
            self.assertAlmostEqual(length, math.sqrt(3))

    def test_rest_lengths_translate_and_scale_correctly(self):
        cube = [(x, y, z) for x in (-1, 1) for y in (-1, 1) for z in (-1, 1)]
        base = fan_spoke_lengths(cube)
        shifted = fan_spoke_lengths([(x + 10000, y - 20, z + 50) for x, y, z in cube])
        scaled = fan_spoke_lengths([(2 * x, 2 * y, 2 * z) for x, y, z in cube])
        for a, b, c in zip(base, shifted, scaled):
            self.assertAlmostEqual(a, b)
            self.assertAlmostEqual(2 * a, c)

    def test_fixture_enables_feature_and_checks_runtime_stability(self):
        settings = PROJECT.read_text(encoding="utf-8")
        fixture = FIXTURE.read_text(encoding="utf-8")
        self.assertIn("soft_body_volume_preservation=true", settings)
        self.assertIn("soft_body_volume_radial_springs=true", settings)
        self.assertIn("PhysicsServer3D.soft_body_apply_central_impulse", fixture)
        self.assertIn("PASS: radial convex soft-body elasticity stability", fixture)


if __name__ == "__main__":
    unittest.main()
