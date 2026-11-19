"""Jolt advanced cloth: long-range tethers follow mesh rest-length scaling.

Godot SoftBody3D shrinking_factor changes the preferred lengths of all
edge springs. Jolt tethers now need to use the same scale or they keep
a contradictory maximum anchor distance after contraction/expansion.
"""

from pathlib import Path
import math
import random
import unittest


ROOT = Path(__file__).resolve().parents[2]
CPP = ROOT / "modules/jolt_physics/objects/jolt_soft_body_3d.cpp"
JOLT_H = ROOT / "thirdparty/jolt_physics/Jolt/Physics/SoftBody/SoftBodySharedSettings.h"
RUNTIME = ROOT / "tests/stress/physics_jolt_softbody_lra_shrink_regression.gd"


def scaled_rest_lengths(original_edge: float, original_tether: float, shrinking_factor: float):
    multiplier = 1.0 - shrinking_factor
    return original_edge * multiplier, original_tether * multiplier


class JoltSoftBodyLRAShrinkTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.code = CPP.read_text(encoding="utf-8")
        cls.lra_header = JOLT_H.read_text(encoding="utf-8")
        cls.mesh = cls.code.split(
            "JPH::SoftBodySharedSettings *JoltSoftBody3D::_create_shared_settings() {", 1
        )[1].split("\nvoid JoltSoftBody3D::_apply_environmental_forces(", 1)[0]

    def test_lra_tethers_scale_with_existing_edge_constraints(self):
        m = self.mesh
        self.assertIn("const float multiplier = 1.0f - shrinking_factor;", m)
        self.assertIn("for (JPH::SoftBodySharedSettings::Edge &e : settings->mEdgeConstraints)", m)
        self.assertIn("e.mRestLength *= multiplier;", m)
        self.assertIn("if (multiplier != 1.0f) {", m)
        self.assertIn("for (JPH::SoftBodySharedSettings::LRA &tether : settings->mLRAConstraints)", m)
        self.assertLess(m.index("if (multiplier != 1.0f) {"),
                        m.index("tether.mMaxDistance *= multiplier;"))
        self.assertIn("tether.mMaxDistance *= multiplier;", m)
        self.assertIn("float mMaxDistance = 0.0f;", self.lra_header)
        self.assertLess(m.index("settings->CreateConstraints(&vertex_attrib"),
                        m.index("tether.mMaxDistance *= multiplier;"))
        self.assertLess(m.index("tether.mMaxDistance *= multiplier;"),
                        m.index("settings->Optimize();"))

    def test_disabled_mode_preserves_original_fast_path(self):
        m = self.mesh
        self.assertIn("if (JoltProjectSettings::soft_body_lra_mode != 0)", m)
        self.assertIn("if (has_kinematic_vertex)", m)
        self.assertIn("vertex_attrib.mLRAType", m)
        self.assertNotIn("settings->mLRAConstraints.emplace_back(", m)

    def test_expansion_with_negative_shrink_kept_supported(self):
        rng = random.Random(20261119)
        for _ in range(20000):
            edge = 10 ** rng.uniform(-3, 3)
            tether = 10 ** rng.uniform(-3, 3)
            shrink = rng.uniform(-0.9, 0.95)
            scaled_edge, scaled_tether = scaled_rest_lengths(edge, tether, shrink)
            factor = 1 - shrink
            self.assertTrue(math.isfinite(scaled_edge))
            self.assertTrue(math.isfinite(scaled_tether))
            self.assertAlmostEqual(scaled_edge / edge, factor, places=10)
            self.assertAlmostEqual(scaled_tether / tether, factor, places=10)
            self.assertGreaterEqual(scaled_tether, 0.0)
        self.assertEqual(scaled_rest_lengths(2, 5, 0), (2, 5))
        self.assertEqual(scaled_rest_lengths(2, 5, -0.2), (2.4, 6.0))
        self.assertEqual(scaled_rest_lengths(2, 5, 0.2), (1.6, 4.0))

    def test_native_fixture_checks_positive_and_negative_shrink(self):
        script = RUNTIME.read_text(encoding="utf-8")
        self.assertIn("const SHRINK_VALUES := [-0.15, 0.0, 0.25]", script)
        self.assertIn("const GRID := 12", script)
        self.assertIn("const FRAMES := 90", script)
        self.assertIn("PhysicsServer3D.soft_body_set_shrinking_factor", script)
        self.assertIn("PhysicsServer3D.soft_body_pin_point", script)
        self.assertIn("start_distance * (1.0 - SHRINK_VALUES[case_idx]) * slack", script)
        self.assertIn("JOLT_SOFTBODY_LRA_SHRINK_RESULT:", script)
        self.assertIn("Jolt soft-body LRA shrink regression passed.", script)


if __name__ == "__main__":
    unittest.main()
