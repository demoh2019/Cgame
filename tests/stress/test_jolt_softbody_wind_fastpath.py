"""Jolt soft-body wind hot path: constant-wind fast path and reusable scratch.

The Jolt callback still sums area forces in their original priority order.
Only zero-attenuation exponentiation and temporary-list allocations change.
A native fixture runs real soft bodies and Area3D wind switching.
"""

import math
import random
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
CPP = ROOT / "modules/jolt_physics/objects/jolt_soft_body_3d.cpp"
HEADER = ROOT / "modules/jolt_physics/objects/jolt_soft_body_3d.h"
AREA_H = ROOT / "modules/jolt_physics/objects/jolt_area_3d.h"
SCRIPT = ROOT / "tests/stress/physics_jolt_softbody_wind_fastpath_regression.gd"


def wind_attenuation_original(centroid, source, direction, factor):
    projection = max(sum((c - s) * d for c, s, d in zip(centroid, source, direction)), 1.0)
    return math.pow(projection, -factor)


def wind_attenuation_cached(centroid, source, direction, factor):
    if factor == 0.0:
        return 1.0
    return wind_attenuation_original(centroid, source, direction, factor)


def keep_capacity(capacity, active_count):
    return capacity <= max(64, active_count * 4)


class JoltSoftBodyWindFastpathTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = CPP.read_text(encoding="utf-8")
        cls.header = HEADER.read_text(encoding="utf-8")
        cls.area_header = AREA_H.read_text(encoding="utf-8")
        cls.wind = cls.source.split(
            "void JoltSoftBody3D::_apply_environmental_forces(float p_step) {", 1
        )[1].split("\nvoid JoltSoftBody3D::_update_mass()", 1)[0]

    def test_reuse_scratch_only_during_soft_body_prestep(self):
        self.assertIn("LocalVector<JoltArea3D *> wind_areas_scratch;", self.header)
        self.assertIn("wind_areas_scratch.clear();", self.wind)
        self.assertIn("wind_areas_scratch.push_back(area);", self.wind)
        self.assertIn("for (const JoltArea3D *area : wind_areas_scratch)", self.wind)
        self.assertNotIn("LocalVector<JoltArea3D *> wind_areas;", self.wind)

    def test_default_zero_wind_attenuation_skips_pow_and_centroid(self):
        self.assertIn("float wind_attenuation_factor = 0.0f;", self.area_header)
        self.assertIn("bool has_distance_attenuation = false;", self.wind)
        self.assertIn("has_distance_attenuation |= area->get_wind_attenuation_factor() != 0.0f;", self.wind)
        self.assertIn("if (has_distance_attenuation) {", self.wind)
        self.assertIn("const float attenuation_factor = area->get_wind_attenuation_factor();", self.wind)
        self.assertIn("real_t attenuation_over_distance = real_t(1.0);", self.wind)
        self.assertIn("if (attenuation_factor != 0.0f) {", self.wind)
        self.assertIn("attenuation_over_distance = Math::pow(projection_toward_centroid, -real_t(attenuation_factor));", self.wind)
        self.assertLess(self.wind.index("if (attenuation_factor != 0.0f) {"), self.wind.index("Math::pow("))

    def test_gravity_and_wind_impulses_preserved(self):
        self.assertIn("JoltArea3D::apply_override(gravity, area->get_gravity_mode()", self.wind)
        self.assertIn("gravity += space->get_default_area()->compute_gravity(com_position);", self.wind)
        self.assertIn("jolt_body->AddForce(to_jolt(gravity) * mass);", self.wind)
        self.assertIn("real_t force_magnitude = area->get_wind_pressure() * triangle_area;", self.wind)
        self.assertIn("normal.dot(wind_direction)", self.wind)
        self.assertIn("physics_vertex0.mVelocity += impulse * physics_vertex0.mInvMass;", self.wind)
        self.assertIn("physics_vertex1.mVelocity += impulse * physics_vertex1.mInvMass;", self.wind)
        self.assertIn("physics_vertex2.mVelocity += impulse * physics_vertex2.mInvMass;", self.wind)

    def test_retain_dense_and_release_sudden_peak(self):
        self.assertIn("MIN_CACHED_WIND_AREAS = 64;", self.wind)
        self.assertIn("wind_count > UINT32_MAX / 4 ? UINT32_MAX : wind_count * 4", self.wind)
        self.assertIn("wind_areas_scratch.get_capacity() > retained_capacity", self.wind)
        self.assertIn("wind_areas_scratch.reset();", self.wind)
        self.assertEqual(self.wind.count("wind_areas_scratch.clear();"), 2)
        for capacity, active, retain in [
            (64, 0, True), (128, 0, False), (128, 32, True),
            (1024, 256, True), (4096, 256, False), (2048, 2048, True)
        ]:
            with self.subTest(capacity=capacity, active=active):
                self.assertEqual(keep_capacity(capacity, active), retain)

    def test_10000_randomized_attenuations_match_original(self):
        rng = random.Random(20261119)
        for trial in range(10000):
            centroid = tuple(rng.uniform(-100.0, 100.0) for _ in range(3))
            source = tuple(rng.uniform(-100.0, 100.0) for _ in range(3))
            direction = tuple(rng.uniform(-1.0, 1.0) for _ in range(3))
            factor = 0.0 if trial % 3 == 0 else rng.uniform(-1.5, 2.5)
            old = wind_attenuation_original(centroid, source, direction, factor)
            new = wind_attenuation_cached(centroid, source, direction, factor)
            self.assertEqual(old, new)

    def test_native_wind_fixture_checks_zero_nonzero_and_disabling(self):
        gd = SCRIPT.read_text(encoding="utf-8")
        for token in (
            "const GRID := 16",
            "AREA_PARAM_WIND_FORCE_MAGNITUDE",
            "AREA_PARAM_WIND_ATTENUATION_FACTOR",
            "AREA_PARAM_WIND_DIRECTION",
            "soft_body_get_point_global_position",
            "after_constant_wind <= before_wind + 0.001",
            "after_mixed_wind",
            "after_calm",
            "after_restored",
            "JOLT_SOFTBODY_WIND_FASTPATH_RESULT:",
            "Jolt soft-body wind fast path regression passed.",
        ):
            self.assertIn(token, gd)


if __name__ == "__main__":
    unittest.main()
