"""Independent hydrostatic and source contracts for tilted capsule buoyancy.

A capsule is the Minkowski sum of a line segment and a sphere. This suite
uses midpoint quadrature of circular cross sections (rather than the C++
8-point Gauss-Legendre implementation) as an independent high-resolution
reference. Compiled tests=yes Godot and runtime tests are also required.
"""
import math
import random
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
HEADER = ROOT / "servers/physics_fluid_capsule_3d.h"
BODY = ROOT / "modules/godot_physics_3d/godot_body_3d.cpp"
NATIVE = ROOT / "tests/servers/test_physics_fluid_tilted_capsule_3d.cpp"
SCENE = ROOT / "tests/stress/physics_tilted_capsule_buoyancy_3d_regression.gd"


def cross_section(radius, height, transverse):
    """Exact wet area and cross-sectional first moment of a circular disk."""
    if radius <= 0 or height <= -transverse * radius:
        return 0.0, 0.0
    if height >= transverse * radius:
        return math.pi * radius * radius, 0.0
    u = height / (transverse * radius)
    root = math.sqrt(max(0, 1.0 - u*u))
    area = radius*radius*(math.acos(-u) + u*root)
    moment = -2.0/3.0*radius**3*root**3
    return area, moment


def integrate_reference(radius, cylinder_length, axis_y, waterline, intervals=1500):
    """High-resolution midpoint rule along capsule axis in three intervals."""
    beta = math.sqrt(1.0 - axis_y*axis_y)
    half = cylinder_length/(2*radius)
    volume, axial, transverse = 0., 0., 0.
    for start, end in ((-half-1, -half), (-half, half), (half, half+1)):
        if end <= start:
            continue
        width = (end-start)/intervals
        for index in range(intervals):
            t = start+(index+0.5)*width
            cap_distance = max(0.0, abs(t)-half)
            disk = math.sqrt(max(0.0, 1.0-cap_distance*cap_distance))
            area, moment = cross_section(
                disk, waterline/radius-axis_y*t, beta)
            volume += area*width
            axial += t*area*width
            transverse += moment*width
    fraction = volume/(math.pi*(cylinder_length/radius+4/3))
    return fraction, (radius*axial/volume, radius*transverse/volume) if volume else (0., 0.)


class TiltedCapsuleBuoyancyContracts(unittest.TestCase):
    def test_horizontal_half_wet_exact_volume_and_center(self):
        radius, cylinder = 1., 2.
        fraction, moments = integrate_reference(radius, cylinder, 0., 0.)
        expected = -(4/3+math.pi/4)/(5*math.pi/3)
        self.assertAlmostEqual(fraction, 0.5, delta=1e-7)
        self.assertAlmostEqual(moments[0], 0., delta=1e-8)
        self.assertAlmostEqual(moments[1], expected, delta=1e-6)
        self.assertNotAlmostEqual(moments[1], -0.5, places=2)

    def test_oblique_capsule_has_horizontal_center_of_buoyancy(self):
        angle = math.sqrt(0.5)
        fraction, moments = integrate_reference(1., 2., angle, 0.)
        beta = math.sqrt(1-angle*angle)
        # Axis in XY at (+beta,+ay): water-plane in-disk projection
        # points (-ay,+beta). This makes a nonzero lateral hydrostatic lever.
        x = beta*moments[0] - angle*moments[1]
        y = angle*moments[0] + beta*moments[1]
        self.assertAlmostEqual(fraction, 0.5, delta=1e-6)
        self.assertLess(x, -0.4)
        self.assertLess(y, -0.6)

    def test_randomized_symmetry_and_buoyancy_moment_conservation(self):
        rng = random.Random(20261119)
        for _ in range(90):
            radius = 10 ** rng.uniform(-1, 0.7)
            cylinder = radius * rng.uniform(0.01, 12)
            ay = rng.uniform(-0.99, 0.99)
            reach = radius + abs(ay)*cylinder/2
            water = reach*rng.uniform(-0.85, 0.85)
            f1, (a1, p1) = integrate_reference(radius, cylinder, ay, water, intervals=1000)
            f2, (a2, p2) = integrate_reference(radius, cylinder, ay, -water, intervals=1000)
            self.assertAlmostEqual(f1+f2, 1., delta=4e-5)
            # The wet part at negative level is the central reflection of
            # the complementary DRY part at positive level.
            self.assertAlmostEqual(f1*a1-f2*a2, 0., delta=4e-4*radius)
            self.assertAlmostEqual(f1*p1-f2*p2, 0., delta=4e-4*radius)
            self.assertTrue(0 <= f1 <= 1)
            self.assertLessEqual(abs(a1), cylinder/2+radius)
            self.assertLessEqual(abs(p1), radius)

    def test_cylinder_fraction_is_not_world_aabb_fraction(self):
        radius, cylinder, ay = 1., 8., 0.8
        surface = -(radius+abs(ay)*cylinder/2)+0.4
        f, _ = integrate_reference(radius, cylinder, ay, surface)
        aabb_fraction = 0.4/(2*(radius+abs(ay)*cylinder/2))
        self.assertGreater(f, 0)
        self.assertNotAlmostEqual(f, aabb_fraction, delta=0.003)

    def test_kernel_is_allocation_free_bounded_and_numerically_safe(self):
        src = HEADER.read_text()
        self.assertIn("godot_physics_fluid_tilted_capsule_sample_3d(", src)
        self.assertIn("godot_physics_fluid_capsule_disk_slice_3d(", src)
        self.assertIn("godot_physics_fluid_capsule_integrate_interval_3d(", src)
        self.assertIn("constexpr int panels = 16;", src)
        self.assertIn("static constexpr double nodes[4]", src)
        self.assertIn("const double first = (offset - transverse_y) / ay;", src)
        self.assertIn("const double second = (offset + transverse_y) / ay;", src)
        self.assertIn("double cuts[4]", src)
        self.assertIn("const double axial_distance = radius * (axial_moment / wet_volume);", src)
        self.assertIn("const double transverse_distance = radius * (transverse_moment / wet_volume);", src)
        self.assertIn("const double fraction = CLAMP(", src)
        self.assertIn("if (!center.is_finite()", src)
        self.assertNotIn("new ", src)
        self.assertNotIn("memalloc", src)

    def test_integration_preserves_exact_vertical_and_invalid_fallback(self):
        src = BODY.read_text()
        self.assertIn('#include "servers/physics_fluid_capsule_3d.h"', src)
        self.assertIn("godot_physics_fluid_capsule_vertical_3d(shape_world.basis, uniform_scale)", src)
        self.assertIn("godot_physics_fluid_tilted_capsule_sample_3d(", src)
        self.assertIn("shape_world.basis.get_column(1) / uniform_scale", src)
        self.assertIn("sample = godot_physics_fluid_sample_3d(bounds, shape_volume, water_height);", src)
        self.assertIn("get_space()->is_fluid_plane_enabled()", src)
        self.assertIn("lever.cross(lift + drag)", src)

    def test_native_and_runtime_tests_are_registered(self):
        native = NATIVE.read_text()
        self.assertIn("TEST_FORCE_LINK(test_physics_fluid_tilted_capsule_3d)", native)
        self.assertEqual(native.count('TEST_CASE("[PhysicsTiltedCapsule]'), 7)
        scene = SCENE.read_text()
        self.assertIn("BODY_STATE_ANGULAR_VELOCITY", scene)
        self.assertIn("capsule_shape_create()", scene)
        self.assertIn("orientation_signs", scene)
        workflow = (ROOT / ".github/workflows/whole-engine-stress.yml").read_text()
        self.assertIn("*[PhysicsTiltedCapsule]*", workflow)


if __name__ == "__main__":
    unittest.main()
