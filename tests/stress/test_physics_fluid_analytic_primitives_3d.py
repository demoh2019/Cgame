"""Independent numerical quadrature and source contracts for primitive buoyancy.

The Python reference integrates actual horizontal cross sections rather
than reusing the closed forms in the C++ helper under test.
"""
from pathlib import Path
import math
import random
import unittest

ROOT = Path(__file__).resolve().parents[2]
HEADER = ROOT / "servers/physics_fluid_buoyancy_3d.h"
BODY = ROOT / "modules/godot_physics_3d/godot_body_3d.cpp"
NATIVE = ROOT / "tests/servers/test_physics_fluid_analytic_primitives_3d.cpp"
HEADLESS = ROOT / "tests/stress/physics_exact_primitive_buoyancy_3d_regression.gd"


def sphere_fraction_and_centroid(radius, height_from_bottom):
    t = min(2.0, max(0.0, height_from_bottom / radius))
    if t == 0:
        return 0.0, None
    return t * t * (3 - t) / 4, -3 * radius * (2 - t) ** 2 / (4 * (3 - t))


def capsule_fraction_and_centroid(radius, cylinder, height_from_bottom):
    t = min(2 + cylinder / radius, max(0.0, height_from_bottom / radius))
    ell = cylinder / radius
    if t == 0:
        return 0.0, None
    if t < 1:
        vol = t * t * (1 - t / 3)
        moment = vol * (1 - 0.75 * (2 - t) ** 2 / (3 - t))
    elif t <= 1 + ell:
        length = t - 1
        vol = 2 / 3 + length
        moment = 5 / 12 + length * (1 + 0.5 * length)
    else:
        u = t - 1 - ell
        upper = u - u ** 3 / 3
        vol = 2 / 3 + ell + upper
        moment = 5 / 12 + ell * (1 + ell / 2) + (1 + ell) * upper + u ** 2 / 2 - u ** 4 / 4
    return vol / (4 / 3 + ell), -radius - cylinder / 2 + radius * moment / vol


def integrate_capsule_cross_sections(radius, cylinder, wet_height, intervals=1500):
    bottom = -(radius + cylinder / 2)
    wet_height = max(0.0, min(2 * radius + cylinder, wet_height))
    if wet_height == 0:
        return 0.0, None
    step = wet_height / intervals
    vol, first_moment = 0.0, 0.0
    for i in range(intervals):
        y = bottom + (i + 0.5) * step
        if abs(y) <= cylinder / 2:
            area = math.pi * radius * radius
        else:
            dist = abs(y) - cylinder / 2
            area = math.pi * max(0, radius * radius - dist * dist)
        dvolume = area * step
        vol += dvolume
        first_moment += dvolume * y
    full_volume = math.pi * radius * radius * (4 * radius / 3 + cylinder)
    return vol / full_volume, first_moment / vol


class AnalyticBuoyancyTests(unittest.TestCase):
    def test_spherical_cap_has_correct_hemisphere_center(self):
        fraction, center = sphere_fraction_and_centroid(1, 1)
        self.assertAlmostEqual(fraction, 0.5)
        self.assertAlmostEqual(center, -3 / 8)
        f1, c1 = sphere_fraction_and_centroid(1, 0.5)
        self.assertAlmostEqual(f1, 0.15625)
        self.assertAlmostEqual(c1, -0.675)
        f2, c2 = sphere_fraction_and_centroid(1, 1.5)
        self.assertAlmostEqual(f2, 0.84375)
        self.assertAlmostEqual(c2, -0.125)

    def test_vertical_capsule_matches_independent_numeric_integration(self):
        rng = random.Random(20261119)
        cases = [(1, 0, 0.5), (1, 2, 0.5), (1, 2, 1), (1, 2, 2),
                 (1, 2, 3), (1, 2, 4)]
        for _ in range(600):
            r = rng.uniform(0.15, 5)
            length = rng.uniform(0, 12)
            height = rng.uniform(0.02, 2 * r + length)
            cases.append((r, length, height))
        for radius, cylinder, wet_height in cases:
            analytic_volume, analytic_center = capsule_fraction_and_centroid(radius, cylinder, wet_height)
            numerical_volume, numerical_center = integrate_capsule_cross_sections(radius, cylinder, wet_height)
            self.assertAlmostEqual(analytic_volume, numerical_volume, delta=2e-5)
            if numerical_volume > 0.0001:
                self.assertAlmostEqual(analytic_center, numerical_center, delta=3e-4 * max(1, radius))
        self.assertEqual(len(cases), 606)

    def test_spherical_limit_and_symmetry(self):
        for radius in (0.2, 1, 7):
            for submerge in (0.05, 0.2, 0.5, 1, 1.5, 1.8, 2):
                sphere = sphere_fraction_and_centroid(radius, radius * submerge)
                capsule = capsule_fraction_and_centroid(radius, 0, radius * submerge)
                self.assertAlmostEqual(sphere[0], capsule[0])
                self.assertAlmostEqual(sphere[1], capsule[1])
                opposite = sphere_fraction_and_centroid(radius, radius * (2 - submerge))
                self.assertAlmostEqual(sphere[0] + opposite[0], 1.0)

    def test_body_uses_primitives_only_for_valid_transforms(self):
        source = BODY.read_text(encoding="utf-8")
        helper = HEADER.read_text(encoding="utf-8")
        self.assertIn("godot_physics_fluid_uniform_scale_3d(shape_world.basis, uniform_scale)", source)
        self.assertIn("PS3DE::SHAPE_SPHERE", source)
        self.assertIn("PS3DE::SHAPE_CAPSULE", source)
        self.assertIn("godot_physics_fluid_sphere_sample_3d(", source)
        self.assertIn("godot_physics_fluid_vertical_capsule_sample_3d(", source)
        self.assertIn("godot_physics_fluid_capsule_vertical_3d(", source)
        self.assertGreaterEqual(source.count("sample = godot_physics_fluid_sample_3d(bounds, shape_volume, water_height);"), 2)
        self.assertIn("p_world_volume * sample.submerged_fraction", helper)
        self.assertIn("moment_units / volume_units", helper)
        self.assertIn("get_column(1)", helper)

    def test_native_and_engine_regressions(self):
        native = NATIVE.read_text(encoding="utf-8")
        script = HEADLESS.read_text(encoding="utf-8")
        self.assertIn("TEST_FORCE_LINK(test_physics_fluid_analytic_primitives_3d)", native)
        self.assertIn("SHAPE_CAPSULE", BODY.read_text(encoding="utf-8"))
        self.assertIn("exact_sphere_sinks", script)
        self.assertIn("exact_capsule_sinks", script)
        self.assertIn("dry_falls_faster", script)
        self.assertIn('"physics/3d/fluid_plane/enabled": true', script)


if __name__ == "__main__":
    unittest.main()
