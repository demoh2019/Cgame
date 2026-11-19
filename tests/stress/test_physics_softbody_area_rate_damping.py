"""Independent numerical and Cgame source contracts for SoftBody3D area-rate damping."""

from __future__ import annotations

import math
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]

# The area Jacobian of the unit right triangle a=(0,0), b=(1,0), c=(0,1).
# These constants come from differentiation of A = 0.5*|(b-a)x(c-a)|,
# rather than from the new engine header.
GRADIENTS = [(-0.5, -0.5), (0.5, 0.0), (0.0, 0.5)]


def damping_step(velocities, inverse_masses, fraction):
    rate = sum(gx * vx + gy * vy
               for (gx, gy), (vx, vy) in zip(GRADIENTS, velocities))
    effective_inverse_mass = sum(w * (gx * gx + gy * gy)
                                 for (gx, gy), w in zip(GRADIENTS, inverse_masses))
    if effective_inverse_mass <= 0:
        return None
    impulse = -fraction * rate / effective_inverse_mass
    return [(vx + w * gx * impulse, vy + w * gy * impulse)
            for (vx, vy), w, (gx, gy)
            in zip(velocities, inverse_masses, GRADIENTS)]


def area_rate(vs):
    return sum(gx * vx + gy * vy for (gx, gy), (vx, vy) in zip(GRADIENTS, vs))


def energy(vs, ws):
    return 0.5 * sum((x*x + y*y) / w
                     for (x, y), w in zip(vs, ws) if w > 0)


def momentum(vs, ws):
    return (sum(x/w for (x, y), w in zip(vs, ws) if w),
            sum(y/w for (x, y), w in zip(vs, ws) if w))


def angular_z(vs, ws):
    # 2D angular momentum for unit triangle with a=(0,0), b=(1,0), c=(0,1).
    return vs[1][1]/ws[1] - vs[2][0]/ws[2]


class SoftBodyAreaRateDampingTests(unittest.TestCase):
    def test_half_fraction_exactly_halves_area_rate(self):
        before = [(0, 0), (2, 0), (0, 0)]
        after = damping_step(before, [1, 1, 1], 0.5)
        self.assertAlmostEqual(area_rate(before), 1.0)
        self.assertAlmostEqual(area_rate(after), 0.5)
        self.assertAlmostEqual(after[0][0], 0.25)
        self.assertAlmostEqual(after[1][0], 1.75)

    def test_full_damping_eliminates_only_area_rate(self):
        before = [(1, -1), (3, 1), (-2, 4)]
        after = damping_step(before, [1, 0.5, 0.25], 1.0)
        self.assertAlmostEqual(area_rate(after), 0.0, places=12)
        self.assertGreater(sum(abs(x) + abs(y) for x, y in after), 0)

    def test_rigid_translation_and_rotation_are_unchanged(self):
        moving = [(3, -2), (3, -2), (3, -2)]
        spinning = [(0, 0), (0, 5), (-5, 0)]
        self.assertEqual(damping_step(moving, [1, 1, 1], 1), moving)
        self.assertEqual(damping_step(spinning, [1, 1, 1], 1), spinning)

    def test_pinned_vertex_does_not_change(self):
        before = [(0, 0), (2, 0), (0, 0)]
        after = damping_step(before, [0, 1, 1], 0.5)
        self.assertEqual(after[0], before[0])
        self.assertAlmostEqual(area_rate(after), 0.5)

    def test_momentum_and_energy(self):
        before = [(1, -1), (3, 1), (-2, 4)]
        ws = [1, 0.5, 0.25]
        initial_energy = energy(before, ws)
        initial_momentum = momentum(before, ws)
        initial_angular = angular_z(before, ws)
        after = damping_step(before, ws, 0.75)
        self.assertLess(energy(after, ws), initial_energy)
        for x, y in zip(momentum(after, ws), initial_momentum):
            self.assertAlmostEqual(x, y, places=12)
        self.assertAlmostEqual(angular_z(after, ws), initial_angular, places=12)

    def test_exponential_fraction_timestep_consistency(self):
        rate = 15.0
        one_step = 1.0 - math.exp(-rate / 60.0)
        half_step = 1.0 - math.exp(-rate / 120.0)
        self.assertAlmostEqual(1.0 - (1.0 - half_step)**2, one_step)

    def test_default_off_and_space_setting(self):
        settings = (ROOT / "servers/physics_3d/physics_server_3d.cpp").read_text()
        space_h = (ROOT / "modules/godot_physics_3d/godot_space_3d.h").read_text()
        space_cpp = (ROOT / "modules/godot_physics_3d/godot_space_3d.cpp").read_text()
        key = "physics/3d/solver/soft_body_area_rate_damping"
        self.assertIn(f'"{key}", PROPERTY_HINT_RANGE, "0,1000,0.1,or_greater,suffix:1/s"), 0.0', settings)
        self.assertIn("soft_body_area_rate_damping = 0.0", space_h)
        self.assertIn("get_soft_body_area_rate_damping()", space_h)
        self.assertIn(f'GLOBAL_GET("{key}")', space_cpp)
        self.assertIn("Math::is_finite(configured_area_damping)", space_cpp)

    def test_pre_constraint_velocity_stage_and_no_buffers(self):
        soft = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.cpp").read_text()
        helper = (ROOT / "servers/physics_softbody_area_rate_damping.h").read_text()
        self.assertIn('"servers/physics_softbody_area_rate_damping.h"', soft)
        self.assertIn("physics_softbody_damp_triangle_area_rate(a.x, b.x, c.x", soft)
        self.assertLess(soft.index("physics_softbody_damp_triangle_area_rate(a.x, b.x, c.x"),
                        soft.index("// Solve velocities."))
        self.assertIn("1.0 - Math::exp(-double(area_damping) * double(p_delta))", soft)
        self.assertIn("if (area_damping > real_t(0.0)", soft)
        self.assertIn("effective_inverse_mass += inv[i] * grad_sq", helper)
        self.assertIn("r_v_a = next[0]", helper)
        self.assertIn("r_v_c = next[2]", helper)
        self.assertLess(helper.index("Math::abs(component) > max_component"),
                        helper.index("r_v_a = next[0]"))
        self.assertNotIn("memnew(", helper)

    def test_native_regression_cases_are_present(self):
        native = (ROOT / "tests/servers/test_physics_softbody_area_rate_damping.cpp").read_text()
        self.assertIn("TEST_FORCE_LINK(test_physics_softbody_area_rate_damping)", native)
        self.assertGreaterEqual(native.count("TEST_CASE("), 13)
        for term in ("linear momentum", "angular momentum", "Kinetic energy",
                     "Microscopic triangles", "Pure angular rigid motion"):
            self.assertIn(term, native)


if __name__ == "__main__":
    unittest.main()
