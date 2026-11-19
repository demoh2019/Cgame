"""Finite XPBD compliance and safe indexed mesh conversion for Jolt SoftBody3D.

Source contracts exercise control flow and an independent numerical model.
Native Godot/Jolt regression checks that the actual simulation stays finite
at zero stiffness and zero/negative requested precision.
"""

import math
import random
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "modules/jolt_physics/objects/jolt_soft_body_3d.cpp"
JOLT_SETTINGS = ROOT / "thirdparty/jolt_physics/Jolt/Physics/SoftBody/SoftBodySharedSettings.h"
SCRIPT = ROOT / "tests/stress/physics_jolt_softbody_constraint_bounds_regression.gd"
FLOAT_MAX = 3.4028234663852886e38
FLOAT_MIN_NORMAL = 1.1754943508222875e-38


def compliance(stiffness, precision, mass, vertex_count, ticks=60.0):
    precision = max(precision, 1)
    dt = 1.0 / ticks / precision
    inv_mass_sum = 2.0 * vertex_count / mass
    if stiffness <= 0.0:
        return FLOAT_MAX
    value = dt * dt * (1.0 / max(stiffness, FLOAT_MIN_NORMAL) - 1.0) * inv_mass_sum
    return min(value, FLOAT_MAX)


def valid_triangle_index_buffer(vertices, indices):
    if not indices or len(indices) % 3 != 0 or not vertices:
        return False
    return all(0 <= idx < len(vertices) for idx in indices)


class JoltSoftBodyConstraintBoundsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.code = SOURCE.read_text(encoding="utf-8")
        cls.mesh = cls.code.split(
            "JPH::SoftBodySharedSettings *JoltSoftBody3D::_create_shared_settings() {", 1
        )[1].split("\nvoid JoltSoftBody3D::_apply_environmental_forces(", 1)[0]
        cls.setter = cls.code.split(
            "void JoltSoftBody3D::set_simulation_precision(int p_precision) {", 1
        )[1].split("\nvoid JoltSoftBody3D::set_mass(", 1)[0]

    def test_mesh_indices_checked_before_any_jolt_vertex_allocation(self):
        m = self.mesh
        self.assertIn("mesh_index_count % 3 != 0", m)
        self.assertIn("mesh_index < 0 || mesh_index >= mesh_vertex_count", m)
        self.assertIn("for (int mesh_index : mesh_indices)", m)
        self.assertLess(m.index("mesh_index_count % 3 != 0"), m.index("new JPH::SoftBodySharedSettings()"))
        self.assertLess(m.index("mesh_index < 0 || mesh_index >= mesh_vertex_count"), m.index("new JPH::SoftBodySharedSettings()"))
        self.assertLess(m.index("new JPH::SoftBodySharedSettings()"), m.index("mesh_to_physics.resize(mesh_vertex_count);"))

    def test_validation_accepts_valid_and_rejects_malformed_meshes(self):
        vertices = [(0, 0), (1, 0), (0, 1)]
        self.assertTrue(valid_triangle_index_buffer(vertices, [0, 1, 2]))
        self.assertTrue(valid_triangle_index_buffer(vertices, [2, 1, 0, 0, 1, 2]))
        for indices in ([], [0, 1], [-1, 1, 2], [0, 3, 2], [0, 1, 2, 4]):
            with self.subTest(indices=indices):
                self.assertFalse(valid_triangle_index_buffer(vertices, indices))

    def test_clamped_iteration_count_prevents_zero_step_division(self):
        self.assertIn("const int precision = MAX(p_precision, 1);", self.setter)
        self.assertIn("if (unlikely(simulation_precision == precision))", self.setter)
        self.assertIn("simulation_precision = precision;", self.setter)
        self.assertIn("const float dt = 1.0f / Engine::get_singleton()->get_user_physics_ticks_per_second() / simulation_precision;", self.mesh)
        self.assertNotIn("simulation_precision = MAX(p_precision, 0);", self.setter)

    def test_zero_stiffness_maps_to_documented_jolt_disabled_edge(self):
        self.assertIn("const float inverse_stiffness = stiffness_coefficient <= 0.0f ?", self.mesh)
        self.assertIn("FLT_MAX : float(MIN(inverse_stiffness_unbounded, double(FLT_MAX)));", self.mesh)
        self.assertIn("const double w1_plus_w2 = 2.0 * double(physics_vertices.size()) / double(mass);", self.mesh)
        self.assertIn("double(MAX(stiffness_coefficient, FLT_MIN))", self.mesh)
        self.assertIn("Set to FLT_MAX to disable regular edges", JOLT_SETTINGS.read_text(encoding="utf-8"))
        self.assertIn("vertex_attrib.mCompliance = vertex_attrib.mShearCompliance = inverse_stiffness;", self.mesh)

    def test_extreme_soft_body_inputs_remain_finite(self):
        self.assertEqual(compliance(0.0, 0, 1.0, 4), FLOAT_MAX)
        self.assertEqual(compliance(0.0, -30, 0.1, 1024), FLOAT_MAX)
        self.assertEqual(compliance(1.0, 1, 1.0, 128), 0.0)
        rng = random.Random(20261119)
        for _ in range(10000):
            stiffness = 0.0 if rng.randrange(17) == 0 else 10.0 ** rng.uniform(-37, 0)
            mass = 10.0 ** rng.uniform(-30, 12)
            precision = rng.randrange(-10, 1024)
            vertices = rng.randrange(3, 2**18)
            value = compliance(stiffness, precision, mass, vertices)
            self.assertTrue(math.isfinite(value))
            self.assertGreaterEqual(value, 0.0)
            self.assertLessEqual(value, FLOAT_MAX)

    def test_mass_and_stiffness_nan_rejected(self):
        self.assertIn("p_mass <= 0.0f || !Math::is_finite(p_mass)", self.code)
        self.assertIn("ERR_FAIL_COND(!Math::is_finite(p_coefficient));", self.code)

    def test_native_fixture_covers_compliance_and_precision_edges(self):
        gd = SCRIPT.read_text(encoding="utf-8")
        for needle in (
            '"stiffness": 0.0, "precision": 0',
            '"stiffness": 0.0, "precision": -3',
            '"stiffness": 1.0, "precision": 7',
            "PhysicsServer3D.soft_body_set_linear_stiffness",
            "PhysicsServer3D.soft_body_get_simulation_precision",
            "soft_body_get_point_global_position",
            "JOLT_SOFTBODY_CONSTRAINT_BOUNDS_RESULT:",
            "Jolt soft-body constraint bounds regression passed.",
        ):
            self.assertIn(needle, gd)


if __name__ == "__main__":
    unittest.main()
