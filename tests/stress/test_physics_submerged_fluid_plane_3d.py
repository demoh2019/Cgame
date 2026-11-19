"""Source/data-flow contracts for opt-in 3D submerged-plane fluid physics.

This complements, but never replaces, C++ unit tests and headless Godot.
"""
from pathlib import Path
import math
import random
import unittest

ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "servers/physics_fluid_buoyancy_3d.h"
BODY = ROOT / "modules/godot_physics_3d/godot_body_3d.cpp"
SPACE_H = ROOT / "modules/godot_physics_3d/godot_space_3d.h"
SPACE_CPP = ROOT / "modules/godot_physics_3d/godot_space_3d.cpp"
SETTINGS = ROOT / "servers/physics_3d/physics_server_3d.cpp"
SCENARIO = ROOT / "tests/stress/physics_submerged_fluid_plane_3d_regression.gd"


def sample(bottom, height, shape_volume, surface_y):
    if height <= 0 or shape_volume <= 0:
        return 0.0, 0.0, 0.0
    wet_h = min(height, max(0, surface_y - bottom))
    fraction = wet_h / height
    return shape_volume * fraction, fraction, bottom + wet_h * 0.5


def drag(relative_velocity, bounds_size, fraction, density, coefficient):
    speed = math.sqrt(sum(v * v for v in relative_velocity))
    if speed == 0:
        return tuple(0.0 for v in relative_velocity)
    unit = tuple(v / speed for v in relative_velocity)
    x, y, z = map(abs, unit)
    dx, dy, dz = bounds_size
    area = x * dy * dz + y * dx * dz + z * dx * dy
    scale = -0.5 * density * coefficient * fraction * area * speed
    return tuple(v * scale for v in relative_velocity)


class FluidPlaneTests(unittest.TestCase):
    def test_volume_fraction_and_center_are_bounded(self):
        rng = random.Random(31277)
        for _ in range(20_000):
            bottom = rng.uniform(-100, 100)
            height = rng.uniform(0.01, 10)
            volume = rng.uniform(0.01, 20)
            surface = rng.uniform(-100, 100)
            wet, fraction, center = sample(bottom, height, volume, surface)
            self.assertLessEqual(0.0, wet)
            self.assertLessEqual(wet, volume + 1e-12)
            self.assertLessEqual(0.0, fraction)
            self.assertLessEqual(fraction, 1.0)
            if fraction > 0:
                self.assertGreaterEqual(center, bottom - 1e-12)
                self.assertLessEqual(center, min(surface, bottom + height) + 1e-12)

    def test_drag_opposes_flow_and_scales_quadratically(self):
        rng = random.Random(1295)
        for _ in range(8_000):
            v = tuple(rng.uniform(-15, 15) for _ in range(3))
            box = tuple(rng.uniform(0.1, 10) for _ in range(3))
            f = drag(v, box, 0.7, 2.0, 1.0)
            self.assertLessEqual(sum(a * b for a, b in zip(f, v)), 1e-9)
            scaled = drag(tuple(2 * x for x in v), box, 0.7, 2.0, 1.0)
            for a, b in zip(f, scaled):
                self.assertAlmostEqual(b, 4 * a, delta=1e-8 * max(1, abs(b)))

    def test_settings_and_space_cache_are_connected(self):
        settings = SETTINGS.read_text(encoding="utf-8")
        header = SPACE_H.read_text(encoding="utf-8")
        space = SPACE_CPP.read_text(encoding="utf-8")
        for prop in ("enabled", "surface_height", "density", "drag_coefficient", "angular_drag", "flow_velocity"):
            key = "physics/3d/fluid_plane/" + prop
            self.assertIn(key, settings)
            self.assertIn(key, space)
        self.assertIn("bool fluid_plane_enabled = false;", header)
        self.assertIn("is_fluid_plane_enabled()", header)

    def test_rigid_body_applies_lift_torque_and_relative_drag(self):
        code = BODY.read_text(encoding="utf-8")
        self.assertIn("!get_space()->is_fluid_plane_enabled() && get_space()->get_fluid_buoyancy()", code)
        self.assertIn("if (get_space()->is_fluid_plane_enabled()", code)
        self.assertIn("if (is_shape_disabled(i))", code)
        self.assertIn("get_shape_area(i)", code)
        self.assertIn("get_shape_aabb(i)", code)
        self.assertIn("godot_physics_fluid_sample_3d(", code)
        self.assertIn("const Vector3 lift = -gravity * (density * sample.submerged_volume);", code)
        self.assertIn("linear_velocity + angular_velocity.cross(lever) - flow_velocity", code)
        self.assertIn("godot_physics_fluid_quadratic_drag_3d(", code)
        self.assertIn("torque += lever.cross(lift + drag);", code)
        self.assertIn("godot_physics_fluid_angular_damping_3d(", code)

    def test_helper_and_engine_regression_present(self):
        helper = HELPER.read_text(encoding="utf-8")
        script = SCENARIO.read_text(encoding="utf-8")
        self.assertIn("p_volume * sample.submerged_fraction", helper)
        self.assertIn("p_world_bounds.get_center()", helper)
        self.assertIn("real_t(0.5) * p_density", helper)
        self.assertIn("const SETTINGS :=", script)
        for name in ("full_floats", "partial_floats", "dry_falls", "current_moves_wet", "offcenter_torque", "off_is_legacy"):
            self.assertIn(name, script)


if __name__ == "__main__":
    unittest.main()
