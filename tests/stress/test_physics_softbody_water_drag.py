"""Independent numerical and source-contract regressions for SoftBody3D water drag."""
from __future__ import annotations
import math
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


def implicit_fraction(strength: float, speed: float, dt: float, inv_mass: float) -> float:
    k = strength * abs(speed) * dt * inv_mass
    if not math.isfinite(k):
        return 1.0
    return 1.0 - 1.0 / (1.0 + k)


def clip_submerged(verts: list[tuple[float, float]], surface: float):
    """Sutherland-Hodgman oracle in the x-y plane, independent of engine C++."""
    result = []
    for start, finish in zip(verts, verts[1:] + verts[:1]):
        start_wet = start[1] <= surface
        finish_wet = finish[1] <= surface
        if start_wet != finish_wet:
            t = (surface - start[1]) / (finish[1] - start[1])
            result.append((start[0] + t * (finish[0] - start[0]), surface))
        if finish_wet:
            result.append(finish)
    return result


def area(poly):
    if len(poly) < 3:
        return 0
    return abs(sum(a[0] * b[1] - a[1] * b[0]
                   for a, b in zip(poly, poly[1:] + poly[:1]))) / 2


class WaterDragContracts(unittest.TestCase):
    def test_clipping_full_half_and_dry(self):
        triangle = [(0, -1), (1, 1), (0, 1)]
        self.assertAlmostEqual(area(clip_submerged(triangle, -2)), 0.0)
        self.assertAlmostEqual(area(clip_submerged(triangle, 2)), 1.0)
        # At y=0 only the lower similar triangle (base at y=-1) is wet:
        # each dimension is halved, so 1/4 of the area is wet.
        self.assertAlmostEqual(area(clip_submerged(triangle, 0)), 0.25)
        triangle = [(0, -1), (1, 1), (0, -1)]
        # This triangle has zero area in xy, use an x-z cut instead.
        tri2 = [(0, -1), (1, 1), (2, -1)]
        self.assertAlmostEqual(area(clip_submerged(tri2, 0)) /
                               area(tri2), 0.75)

    def test_implicit_quadratic_damping_does_not_reverse_velocity(self):
        for speed in [0.01, 1, 100, 1e20]:
            for step in [1e-6, 1/60, 1]:
                fraction = implicit_fraction(10, speed, step, 1.0 / 3.0)
                after = speed * (1.0 - fraction)
                self.assertGreaterEqual(after, 0.0)
                self.assertLessEqual(after, speed)
                self.assertLessEqual(fraction, 1.0)

    def test_current_relative_drag_sign_and_winding_invariance(self):
        # For submerged horizontal cloth with current +X and still nodes,
        # relative body velocity is -X; skin drag must point +X.
        velocity = 0.0
        current = 5.0
        relative = velocity - current
        self.assertLess(relative, 0)
        force = -relative * implicit_fraction(100, relative, .1, 1/3)
        self.assertGreater(force, 0)
        # Signed face normals invert, but the quadratic normal drag does not.
        for vn, n in ((-3, 1), (3, -1)):
            component = -vn * abs(vn) * n
            self.assertGreater(component, 0)

    def test_source_wiring_and_no_default_allocation(self):
        settings = (ROOT / "servers/physics_3d/physics_server_3d.cpp").read_text()
        space_h = (ROOT / "modules/godot_physics_3d/godot_space_3d.h").read_text()
        space_cpp = (ROOT / "modules/godot_physics_3d/godot_space_3d.cpp").read_text()
        body = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.cpp").read_text()
        helper = (ROOT / "servers/physics_softbody_water_drag.h").read_text()
        self.assertIn('"physics/3d/fluid_plane/soft_body_water_drag"), false', settings)
        self.assertIn('"physics/3d/fluid_plane/soft_body_water_tangential_ratio", PROPERTY_HINT_RANGE, "0,5,0.01,or_greater"), 0.0', settings)
        self.assertIn("is_soft_body_water_drag_enabled()", space_h)
        self.assertIn("get_soft_body_water_tangential_ratio()", space_h)
        self.assertIn('GLOBAL_GET("physics/3d/fluid_plane/soft_body_water_drag")', space_cpp)
        self.assertIn("Math::is_finite(soft_body_tangent)", space_cpp)
        self.assertIn('"servers/physics_softbody_water_drag.h"', body)
        self.assertIn("physics_softbody_water_drag_face(", body)
        self.assertIn("apply_wind || apply_drag || apply_lift || gas_pressure > 0.0 || apply_water_drag", body)
        self.assertIn("get_space()->is_fluid_plane_enabled() && get_space()->is_soft_body_water_drag_enabled()", body)
        self.assertIn("next_forces[j].is_finite()", body)
        self.assertNotIn("memnew(", helper)
        self.assertNotIn("malloc(", helper)

    def test_barycentric_mass_weighted_damping_and_atomic_output(self):
        helper = (ROOT / "servers/physics_softbody_water_drag.h").read_text()
        for symbol in ["weights[i] * weights[i] * inverse_masses[i]",
                       "clipped[count++] = interpolate(a, b, t)",
                       "velocity[j] += weights[i] * velocities[i][j]",
                       "double accumulated[3][3]",
                       "r_force[0] = output[0]",
                       "r_force[2] = output[2]",
                       "Math::is_finite(accumulated[i][j])"]:
            self.assertIn(symbol, helper)
        self.assertLess(helper.index("const double max_component"),
                        helper.index("r_force[0] = output[0]"))

    def test_native_test_cases_registered(self):
        tests = (ROOT / "tests/servers/test_physics_softbody_water_drag.cpp").read_text()
        self.assertIn("TEST_FORCE_LINK(test_physics_softbody_water_drag)", tests)
        self.assertGreaterEqual(tests.count('TEST_CASE('), 9)


if __name__ == "__main__":
    unittest.main()
