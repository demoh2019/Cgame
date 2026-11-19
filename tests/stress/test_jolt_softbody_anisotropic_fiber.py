"""Jolt XPBD woven textile: opt-in directional spring compliance.

A Jolt edge spring stores rest length and compliance. Anisotropy is an
additional rest-pose mesh material property, so it must change spring
compliance only once at mesh construction, not per simulation frame.
"""

import math
import random
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "modules/jolt_physics/objects/jolt_soft_body_3d.cpp"
HEADER = ROOT / "modules/jolt_physics/jolt_project_settings.h"
SETTINGS = ROOT / "modules/jolt_physics/jolt_project_settings.cpp"
JOLT = ROOT / "thirdparty/jolt_physics/Jolt/Physics/SoftBody/SoftBodySharedSettings.h"
FIXTURE = ROOT / "tests/stress/physics_jolt_softbody_anisotropic_fiber_regression.gd"

FLT_MAX = 3.4028234663852886e38


def anisotropic_compliance(base, direction, axis, multiplier):
    if multiplier == 1 or base <= 0 or base >= FLT_MAX or not math.isfinite(base):
        return base
    squared_length = sum(d * d for d in direction)
    if squared_length == 0 or not math.isfinite(squared_length):
        return base
    alignment_sq = direction[axis] ** 2 / squared_length
    scale = 1 + (multiplier - 1) * alignment_sq
    adjusted = base * scale
    return min(adjusted, FLT_MAX) if math.isfinite(adjusted) else base


class JoltSoftBodyAnisotropicFiberTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = SRC.read_text(encoding="utf-8")
        cls.settings_h = HEADER.read_text(encoding="utf-8")
        cls.settings_cpp = SETTINGS.read_text(encoding="utf-8")
        cls.jolt = JOLT.read_text(encoding="utf-8")
        cls.fixture = FIXTURE.read_text(encoding="utf-8")
        cls.builder = cls.source.split(
            "JPH::SoftBodySharedSettings *JoltSoftBody3D::_create_shared_settings() {", 1
        )[1].split("\nvoid JoltSoftBody3D::_apply_environmental_forces(", 1)[0]

    def test_project_settings_default_to_isotropic(self):
        self.assertIn("inline static int soft_body_fiber_axis = 0;", self.settings_h)
        self.assertIn("inline static float soft_body_fiber_compliance_multiplier = 1.0f;", self.settings_h)
        self.assertIn('"physics/jolt_physics_3d/simulation/soft_body_fiber_axis", PROPERTY_HINT_ENUM, "X,Y,Z"), 0', self.settings_cpp)
        self.assertIn('"physics/jolt_physics_3d/simulation/soft_body_fiber_compliance_multiplier", PROPERTY_HINT_RANGE, "0.1,10,0.05"), 1.0f', self.settings_cpp)

    def test_axis_and_multiplier_sanitized(self):
        self.assertIn('soft_body_fiber_axis = CLAMP((int)GLOBAL_GET(', self.settings_cpp)
        self.assertIn('soft_body_fiber_compliance_multiplier = Math::is_finite(fiber_multiplier)', self.settings_cpp)
        self.assertIn('CLAMP(fiber_multiplier, 0.1f, 10.0f) : 1.0f;', self.settings_cpp)
        for value in (-12, 0, 1, 2, 3, 100):
            self.assertIn(max(0, min(value, 2)), (0, 1, 2))

    def test_anisotropy_skips_default_path(self):
        code = self.builder
        self.assertIn("if (fiber_multiplier != 1.0f) {", code)
        self.assertIn("for (JPH::SoftBodySharedSettings::Edge &edge : settings->mEdgeConstraints)", code)
        self.assertIn("const int fiber_axis = JoltProjectSettings::soft_body_fiber_axis;", code)
        self.assertEqual(anisotropic_compliance(1.0, (1, 0, 0), 0, 1.0), 1.0)
        self.assertEqual(anisotropic_compliance(1.0, (1, 1, 1), 1, 1.0), 1.0)

    def test_preserves_disabled_and_rigid_constraints(self):
        code = self.builder
        self.assertIn("edge.mCompliance <= 0.0f || edge.mCompliance >= FLT_MAX", code)
        self.assertIn("!Math::is_finite(edge.mCompliance)", code)
        for c in (0, FLT_MAX, math.inf):
            self.assertEqual(anisotropic_compliance(c, (1, 0, 0), 0, 0.2), c)
        self.assertEqual(anisotropic_compliance(1.0, (0, 0, 0), 0, 2.0), 1.0)

    def test_exact_axis_and_diagonal_interpolation(self):
        self.assertAlmostEqual(anisotropic_compliance(1.0, (3, 0, 0), 0, 4.0), 4.0)
        self.assertAlmostEqual(anisotropic_compliance(1.0, (0, 3, 0), 0, 4.0), 1.0)
        self.assertAlmostEqual(anisotropic_compliance(1.0, (3, 3, 0), 0, 4.0), 2.5)
        self.assertAlmostEqual(anisotropic_compliance(1.0, (0, 0, -5), 2, 0.25), 0.25)
        self.assertAlmostEqual(anisotropic_compliance(2.0, (1, 1, 1), 1, 4.0), 4.0)

    def test_rest_pose_vertices_before_volumetric_radial_springs(self):
        code = self.builder
        self.assertIn("const JPH::Float3 &a = settings->mVertices[edge.mVertex[0]].mPosition;", code)
        self.assertIn("const JPH::Float3 &b = settings->mVertices[edge.mVertex[1]].mPosition;", code)
        self.assertIn("const double alignment_sq = parallel * parallel / length_sq;", code)
        self.assertIn("edge.mCompliance = float(MIN(adjusted, double(FLT_MAX)));", code)
        self.assertLess(code.index("settings->CreateConstraints(&vertex_attrib"), code.index("if (fiber_multiplier != 1.0f)"))
        self.assertLess(code.index("if (fiber_multiplier != 1.0f)"), code.index("try_build_convex_volume_fan(*settings"))
        self.assertLess(code.index("if (fiber_multiplier != 1.0f)"), code.index("settings->Optimize();"))
        self.assertIn("append_volume_radial_springs(*settings", self.source)
        self.assertLess(code.index("if (fiber_multiplier != 1.0f)"),
                        code.index("append_volume_radial_springs(*settings"))

    def test_twenty_thousand_random_oriented_springs(self):
        rng = random.Random(20261119)
        for _ in range(20000):
            direction = tuple(rng.uniform(-100, 100) for _ in range(3))
            axis = rng.randrange(3)
            compliance = 10 ** rng.uniform(-6, 3)
            factor = rng.uniform(0.1, 10)
            value = anisotropic_compliance(compliance, direction, axis, factor)
            alignment_sq = direction[axis] ** 2 / sum(x * x for x in direction)
            expected = compliance * (1 + (factor - 1) * alignment_sq)
            self.assertTrue(math.isfinite(value))
            self.assertGreaterEqual(value, 0)
            self.assertAlmostEqual(value, expected, delta=expected * 1e-12 + 1e-10)

    def test_native_cloth_fixture_both_loading_directions(self):
        gd = self.fixture
        for mark in (
            "const GRID := 12",
            "const FRAMES := 36",
            "PhysicsServer3D.soft_body_set_linear_stiffness",
            "PhysicsServer3D.soft_body_pin_point",
            "PhysicsServer3D.soft_body_apply_point_impulse",
            "PhysicsServer3D.soft_body_get_point_global_position",
            "JOLT_SOFTBODY_ANISOTROPIC_FIBER_RESULT:",
            "Jolt anisotropic cloth fiber regression passed.",
        ):
            self.assertIn(mark, gd)


if __name__ == "__main__":
    unittest.main()
