"""Cgame rotating non-inertial reference frame numerical and source contracts.

Coriolis is integrated by the Boris/Cayley scheme; centrifugal and
Euler accelerations are symmetrically kicked at a frozen COM position.
Tests are independent of the native C++ implementation.
"""

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


def add(a, b):
    return tuple(x+y for x, y in zip(a, b))


def minus(a, b):
    return tuple(x-y for x, y in zip(a, b))


def mul(a, scalar):
    return tuple(scalar*x for x in a)


def norm(a):
    return math.sqrt(dot(a, a))


def rotate_boris(velocity, omega, dt):
    """Exact Cayley transform (not exact phase) for dv/dt=-2 Ω×v."""
    t = mul(omega, dt)
    s = mul(t, 2/(1+dot(t, t)))
    prime = add(velocity, cross(velocity, t))
    return add(velocity, cross(prime, s))


def integrate(velocity, position, frame_origin=(0,0,0),
              omega=(0,0,0), alpha=(0,0,0), dt=1/60):
    r = minus(position, frame_origin)
    centrifugal = minus(mul(r, dot(omega, omega)),
                        mul(omega, dot(omega, r)))
    euler = mul(cross(alpha, r), -1)
    acceleration = add(centrifugal, euler)
    half_kick = mul(acceleration, dt/2)
    return add(rotate_boris(add(velocity, half_kick), omega, dt), half_kick)


class RotatingFrameNumericalContracts(unittest.TestCase):
    def test_zero_config_is_exact_noop(self):
        v = (3.,-2.,7.)
        self.assertEqual(integrate(v, (5,6,7)), v)
        self.assertEqual(integrate(v, (5,6,7), omega=(0,0,3), dt=0), v)

    def test_coriolis_direction_and_analytic_cayley_coefficients(self):
        result = integrate((1,0,0), (0,0,0), omega=(0,0,1), dt=.1)
        self.assertAlmostEqual(result[0], .99/1.01, places=12)
        self.assertAlmostEqual(result[1], -.2/1.01, places=12)
        self.assertAlmostEqual(result[2], 0, places=12)

    def test_coriolis_does_zero_work_and_preserves_energy(self):
        v = (2,3,5)
        omega = (1.3,-2.2,7)
        self.assertAlmostEqual(dot(v,cross(omega,v)), 0, places=12)
        for _ in range(200):
            v = integrate(v, (0,0,0), omega=omega, dt=.04)
        self.assertAlmostEqual(norm(v), math.sqrt(38), places=10)

    def test_coarse_timestep_preserves_speed(self):
        for dt in [.01, .1, 1, 10, 100, 1000]:
            v = (1,2,3)
            result = integrate(v, (0,0,0), omega=(0,0,4), dt=dt)
            self.assertAlmostEqual(norm(result), norm(v), places=12)

    def test_reverse_frame_rotation_returns_original(self):
        omega = (0,0,4)
        original=(1,2,3)
        v = integrate(original, (0,0,0), omega=omega, dt=.15)
        v = integrate(v, (0,0,0), omega=mul(omega,-1), dt=.15)
        for x,y in zip(original,v):
            self.assertAlmostEqual(x,y,places=12)

    def test_spin_axis_parallel_motion_is_unaffected(self):
        initial=(0,0,4)
        self.assertEqual(integrate(initial, (0,0,20), omega=(0,0,3), dt=.5), initial)

    def test_centrifugal_acceleration_outward(self):
        v = integrate((0,0,0), (2,0,0), omega=(0,0,3), dt=.001)
        self.assertAlmostEqual(v[0], .018, delta=2e-7)
        self.assertLess(v[1],0)
        self.assertAlmostEqual(v[2],0)

    def test_centrifugal_force_zero_on_axis(self):
        self.assertEqual(integrate((0,0,0), (0,0,100),
                                   omega=(0,0,3), dt=.2),(0,0,0))
        self.assertEqual(integrate((0,0,0), (0,0,0),
                                   omega=(0,0,3), dt=.2),(0,0,0))

    def test_centrifugal_acceleration_scales_quadratically(self):
        a=integrate((0,0,0),(1,0,0),omega=(0,0,1),dt=1e-5)
        b=integrate((0,0,0),(1,0,0),omega=(0,0,2),dt=1e-5)
        self.assertAlmostEqual(b[0]/a[0],4,places=7)

    def test_euler_acceleration_matches_spinup_cross_radius(self):
        v=integrate((0,0,0),(2,0,0),alpha=(0,0,4),dt=.1)
        self.assertAlmostEqual(v[1],-.8,places=12)
        reverse=integrate((0,0,0),(2,0,0),alpha=(0,0,-4),dt=.1)
        self.assertAlmostEqual(reverse[1],.8,places=12)

    def test_translate_frame_origin_and_object_together(self):
        base=integrate((1,-2,3),(2,0,1),omega=(1,2,3),dt=.1)
        o=(1000,-2000,3000)
        moved=integrate((1,-2,3),add((2,0,1),o),
                        frame_origin=o,omega=(1,2,3),dt=.1)
        for x,y in zip(base,moved):
            self.assertAlmostEqual(x,y,places=12)

    def test_reversing_radial_displacement_reverses_acceleration(self):
        a=integrate((0,0,0),(2,0,0),omega=(0,0,3),dt=.03)
        b=integrate((0,0,0),(-2,0,0),omega=(0,0,3),dt=.03)
        for x,y in zip(a,b):
            self.assertAlmostEqual(x,-y,places=12)

    def test_boris_rotation_is_orthogonal_in_3d(self):
        u=(1,0,0);v=(0,1,0);omega=(2,3,4)
        a=rotate_boris(u,omega,.3);b=rotate_boris(v,omega,.3)
        self.assertAlmostEqual(dot(a,b),0,places=12)
        self.assertAlmostEqual(norm(a),1,places=12)
        self.assertAlmostEqual(norm(b),1,places=12)

    def test_project_settings_opt_in_and_sanitized(self):
        server=(ROOT/"servers/physics_3d/physics_server_3d.cpp").read_text()
        space=(ROOT/"modules/godot_physics_3d/godot_space_3d.cpp").read_text()
        space_h=(ROOT/"modules/godot_physics_3d/godot_space_3d.h").read_text()
        keys=["enabled","origin","angular_velocity","angular_acceleration"]
        for name in keys:
            setting="rotating_frame_"+name
            self.assertIn(f'"physics/3d/solver/{setting}"',server)
            self.assertIn(f'GLOBAL_GET("physics/3d/solver/{setting}")',space)
        self.assertIn('"physics/3d/solver/rotating_frame_enabled"), false',server)
        self.assertIn("rotating_frame_enabled = false;",space_h)
        self.assertIn("is_rotating_frame_enabled()",space_h)
        self.assertIn("get_rotating_frame_origin()",space_h)
        self.assertIn("get_rotating_frame_angular_velocity()",space_h)
        self.assertIn("get_rotating_frame_angular_acceleration()",space_h)
        self.assertIn("configured_frame_omega.is_finite()",space)
        self.assertIn("configured_frame_alpha.is_finite()",space)
        self.assertIn("configured_frame_origin.is_finite()",space)
        self.assertIn("CLAMP(configured_frame_omega.x",space)

    def test_rigid_only_and_no_shape_pass_default(self):
        body=(ROOT/"modules/godot_physics_3d/godot_body_3d.cpp").read_text()
        self.assertIn("mode == PS3DE::BODY_MODE_RIGID && get_space()->is_rotating_frame_enabled()",body)
        self.assertIn("godot_physics_rotating_frame_step_3d(linear_velocity, world_com",body)
        self.assertIn("get_transform().origin + center_of_mass",body)
        # After physical force and drag, in the same force-integration block.
        self.assertGreater(body.index("godot_physics_rotating_frame_step_3d"),
                           body.index("linear_velocity += _inv_mass * force * p_step"))
        self.assertGreater(body.index("godot_physics_rotating_frame_step_3d"),
                           body.index("linear_velocity = godot_physics_fluid_linear_drag("))
        self.assertLess(body.index("godot_physics_rotating_frame_step_3d"),
                        body.index("angular_velocity = godot_physics_clamp_angular_velocity("))

    def test_constitutive_centrifugal_and_euler_terms(self):
        header=(ROOT/"servers/physics_rotating_frame_3d.h").read_text()
        self.assertIn("omega_sq * offset[i] - omega_dot_r * omega[i] - euler_cross[i]",header)
        self.assertIn("const double s_factor = 2.0 / (1.0 + t_sq);",header)
        self.assertIn("before[0] + before[1] * t[2] - before[2] * t[1]",header)
        self.assertIn("before[i] + rotate[i] + (before[i] - velocity[i])",header)
        self.assertNotIn("memnew(",header)
        self.assertNotIn("malloc(",header)

    def test_transactional_finite_guard_before_commit(self):
        header=(ROOT/"servers/physics_rotating_frame_3d.h").read_text()
        self.assertIn("double(std::numeric_limits<real_t>::max())",header)
        self.assertIn("!Math::is_finite(result[i])",header)
        self.assertLess(header.index("if (!next_velocity.is_finite())"),
                        header.index("r_velocity = next_velocity;"))
        self.assertIn("p_delta < 0.0",header)

    def test_native_tests_and_workflow(self):
        native=(ROOT/"tests/servers/test_physics_rotating_frame_3d.cpp").read_text()
        action=(ROOT/".github/workflows/physics-rigid-rotating-frame.yml").read_text()
        self.assertIn("TEST_FORCE_LINK(test_physics_rotating_frame_3d)",native)
        self.assertGreaterEqual(native.count("TEST_CASE("),20)
        self.assertIn("Boris Cayley",native)
        self.assertIn("python3 -m unittest discover",action)


if __name__=="__main__":
    unittest.main()
