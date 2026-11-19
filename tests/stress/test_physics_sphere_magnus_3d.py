"""Independent analytical and source-contract tests for RigidBody3D Magnus lift."""

from __future__ import annotations

import math
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


def dot(a, b):
    return sum(x*y for x, y in zip(a, b))


def cross(a, b):
    return (a[1]*b[2]-a[2]*b[1],
            a[2]*b[0]-a[0]*b[2],
            a[0]*b[1]-a[1]*b[0])


def sub(a, b):
    return tuple(x-y for x, y in zip(a, b))


def norm(a):
    return math.sqrt(dot(a, a))


def magnus_force(velocity, omega, flow=(0, 0, 0), radius=.1,
                 density=1.225, coefficient=.2, max_lift=1.5):
    """Reference: bounded spin-dependent lift of a spherical rigid body."""
    u = sub(velocity, flow)
    wu = cross(omega, u)
    vsq = dot(u, u)
    csq = dot(wu, wu)
    if not vsq or not csq or not density or not coefficient or not max_lift:
        return (0., 0., 0.)
    factor = .5 * density * math.pi * radius**2 * min(
        coefficient*radius, max_lift*vsq / math.sqrt(csq))
    return tuple(factor*x for x in wu)


class SphereMagnusContracts(unittest.TestCase):
    def test_reference_force_and_physical_units(self):
        f = magnus_force((10, 0, 0), (0, 0, 100))
        self.assertAlmostEqual(f[1], .38484510006474987, places=12)
        self.assertEqual(f[0], 0)
        self.assertEqual(f[2], 0)

    def test_perpendicular_to_motion_and_angular_velocity(self):
        v, omega = (10, 2, -4), (-2, 3, 100)
        f = magnus_force(v, omega)
        self.assertAlmostEqual(dot(f, v), 0, places=10)
        self.assertAlmostEqual(dot(f, omega), 0, places=10)

    def test_spin_reversal_changes_direction_without_changing_magnitude(self):
        pos = magnus_force((10, 0, 0), (0, 0, 100))
        neg = magnus_force((10, 0, 0), (0, 0, -100))
        self.assertAlmostEqual(pos[1], -neg[1])
        self.assertAlmostEqual(norm(pos), norm(neg))

    def test_medium_and_body_translation_galilean_invariance(self):
        base = magnus_force((10, 0, 0), (0, 0, 100))
        translated = magnus_force((17, -20, 7), (0, 0, 100), (7, -20, 7))
        for a,b in zip(base, translated):
            self.assertAlmostEqual(a, b)

    def test_zero_motion_spin_or_coefficient(self):
        self.assertEqual(magnus_force((0,0,0), (0,0,100)), (0,0,0))
        self.assertEqual(magnus_force((10,0,0), (0,0,0)), (0,0,0))
        self.assertEqual(magnus_force((10,0,0), (100,0,0)), (0,0,0))
        self.assertEqual(magnus_force((10,0,0), (0,0,100), coefficient=0), (0,0,0))
        self.assertEqual(magnus_force((10,0,0), (0,0,100), density=0), (0,0,0))
        self.assertEqual(magnus_force((10,0,0), (0,0,100), max_lift=0), (0,0,0))

    def test_uncapped_radius_cube_scaling(self):
        f1 = norm(magnus_force((10,0,0), (0,0,100), radius=.1))
        f2 = norm(magnus_force((10,0,0), (0,0,100), radius=.2))
        self.assertAlmostEqual(f2/f1, 8)

    def test_uncapped_density_and_coefficient_linear(self):
        base = norm(magnus_force((10,0,0), (0,0,100)))
        doubled_density = norm(magnus_force((10,0,0), (0,0,100), density=2.45))
        doubled_spin = norm(magnus_force((10,0,0), (0,0,100), coefficient=.4))
        self.assertAlmostEqual(doubled_density/base, 2)
        self.assertAlmostEqual(doubled_spin/base, 2)

    def test_lift_coefficient_saturates_at_dynamic_pressure(self):
        speed=10
        force=norm(magnus_force((speed,0,0), (0,0,10000), max_lift=1.5))
        max_force=.5*1.225*math.pi*.1**2*speed**2*1.5
        self.assertAlmostEqual(force, max_force)
        many = norm(magnus_force((speed,0,0), (0,0,100000), max_lift=1.5))
        self.assertAlmostEqual(force, many)

    def test_saturated_quadratic_speed_scaling(self):
        slow=norm(magnus_force((5,0,0), (0,0,10000)))
        fast=norm(magnus_force((10,0,0), (0,0,10000)))
        self.assertAlmostEqual(fast/slow, 4)

    def test_compound_sphere_force_at_offset_creates_torque(self):
        lever=(0,0,1)
        omega=(0,0,100)
        base_v=(10,0,0)
        local_v=tuple(a+b for a,b in zip(base_v,cross(omega,lever)))
        f=magnus_force(local_v,omega)
        torque=cross(lever,f)
        self.assertLess(torque[0], 0)
        self.assertAlmostEqual(dot(torque,lever), 0)

    def test_kinetic_energy_work_zero_in_ideal_continuous_case(self):
        u=(2,3,5)
        omega=(8,11,13)
        force=magnus_force(u,omega)
        self.assertAlmostEqual(dot(force,u),0,places=10)

    def test_settings_registered_and_finite_checked(self):
        server=(ROOT/"servers/physics_3d/physics_server_3d.cpp").read_text()
        space=(ROOT/"modules/godot_physics_3d/godot_space_3d.cpp").read_text()
        space_h=(ROOT/"modules/godot_physics_3d/godot_space_3d.h").read_text()
        for setting in ["spin_coefficient", "medium_density", "max_lift_coefficient", "flow_velocity"]:
            name="sphere_magnus_"+setting
            self.assertIn(f'"physics/3d/solver/{name}"', server)
            self.assertIn(f'GLOBAL_GET("physics/3d/solver/{name}")', space)
            self.assertIn(f"get_{name}()", space_h)
        self.assertIn("sphere_magnus_spin_coefficient = 0.0", space_h)
        self.assertIn("Math::is_finite(configured_magnus_spin)", space)
        self.assertIn("configured_magnus_flow.is_finite()", space)

    def test_default_path_does_not_scan_shapes(self):
        body=(ROOT/"modules/godot_physics_3d/godot_body_3d.cpp").read_text()
        self.assertIn("get_space()->get_sphere_magnus_spin_coefficient() > 0.0",body)
        self.assertIn("mode == PS3DE::BODY_MODE_RIGID",body)
        start=body.index("// Spinning spheres curve")
        guard=body.index("get_space()->get_sphere_magnus_spin_coefficient() > 0.0",start)
        shape_loop=body.index("for (int i = 0; i < sphere_shape_count; ++i)",guard)
        self.assertLess(guard,shape_loop)

    def test_only_uniformly_scaled_spheres_are_supported(self):
        body=(ROOT/"modules/godot_physics_3d/godot_body_3d.cpp").read_text()
        self.assertIn("shape->get_type() != PS3DE::SHAPE_SPHERE",body)
        self.assertIn("is_shape_disabled(i)",body)
        self.assertIn("godot_physics_fluid_uniform_scale_3d(sphere_transform.basis, uniform_scale)",body)
        self.assertIn("static_cast<const GodotSphereShape3D *>(shape)->get_radius() * uniform_scale",body)

    def test_compound_sphere_torque_and_flow(self):
        body=(ROOT/"modules/godot_physics_3d/godot_body_3d.cpp").read_text()
        self.assertIn("linear_velocity + angular_velocity.cross(lever)",body)
        self.assertIn("world_com = get_transform().origin + center_of_mass",body)
        self.assertIn("const Vector3 candidate_torque = torque + lever.cross(lift)",body)
        self.assertIn("const Vector3 candidate_force = force + lift",body)
        self.assertIn("if (!candidate_force.is_finite() || !candidate_torque.is_finite())",body)
        self.assertIn("get_space()->get_sphere_magnus_flow_velocity()",body)

    def test_per_step_impulse_limiter(self):
        body=(ROOT/"modules/godot_physics_3d/godot_body_3d.cpp").read_text()
        self.assertIn("requested_impulse = double(lift_speed) * double(p_step)",body)
        self.assertIn("max_impulse = double(mass) * double(local_speed)",body)
        self.assertIn("if (requested_impulse > max_impulse)",body)
        self.assertIn("lift *= real_t(max_impulse / requested_impulse)",body)

    def test_transactional_helper_and_no_heap_allocations(self):
        header=(ROOT/"servers/physics_sphere_magnus_3d.h").read_text()
        self.assertIn("const double capped_factor = double(p_max_lift_coefficient)",header)
        self.assertIn("const double spin_factor = MIN(uncapped_factor, capped_factor)",header)
        self.assertIn("double(std::numeric_limits<real_t>::max())",header)
        self.assertIn("!Math::is_finite(components[i])",header)
        self.assertIn("r_force = force;",header)
        self.assertNotIn("malloc(",header)
        self.assertNotIn("memnew(",header)

    def test_native_cases_and_actions_registration(self):
        tests=(ROOT/"tests/servers/test_physics_sphere_magnus_3d.cpp").read_text()
        workflow=(ROOT/".github/workflows/physics-sphere-magnus.yml").read_text()
        self.assertIn("TEST_FORCE_LINK(test_physics_sphere_magnus_3d)",tests)
        self.assertGreaterEqual(tests.count("TEST_CASE("),19)
        self.assertIn("python3 -m unittest discover",workflow)


if __name__ == "__main__":
    unittest.main()
