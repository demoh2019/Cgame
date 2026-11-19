"""Analytical six-panel box aerodynamics and GodotPhysics3D wiring contracts.

Run from repository root:
    python3 -m unittest discover -s tests/stress \
        -p test_physics_rigid_box_aero_panels_3d.py -v
"""

from __future__ import annotations

import math
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
AXES = ((1.,0.,0.), (0.,1.,0.), (0.,0.,1.))


def plus(a, b):
    return tuple(x+y for x,y in zip(a,b))


def sub(a, b):
    return tuple(x-y for x,y in zip(a,b))


def scale(a, x):
    return tuple(x*y for y in a)


def dot(a, b):
    return sum(x*y for x,y in zip(a,b))


def cross(a, b):
    return (a[1]*b[2]-a[2]*b[1],
            a[2]*b[0]-a[0]*b[2],
            a[0]*b[1]-a[1]*b[0])


def norm(a):
    return math.sqrt(dot(a,a))


def point_energy(v, w):
    return 0.5*(dot(v,v)+dot(w,w))


def step(v, omega, axes=AXES, box_center=(0.,0.,0.), com=(0.,0.,0.),
         wind=(0.,0.,0.), rho=1., pressure=1., skin=0., invmass=1.,
         inv_inertia=(1.,1.,1.), dt=.01):
    """Independent reference for face-center velocity and impulse projection."""
    linear, angular = tuple(v), tuple(omega)
    for axis in range(3):
        face_normal = cross(axes[(axis+1)%3], axes[(axis+2)%3])
        normal_mag = norm(face_normal)
        if normal_mag == 0 or dot(face_normal,axes[axis]) == 0:
            raise ValueError("singular affine box")
        sign_det = 1 if dot(face_normal, axes[axis]) > 0 else -1
        normal_positive = scale(face_normal, sign_det/normal_mag)
        world_area = 4*normal_mag
        for side_sign in (1,-1):
            normal = scale(normal_positive,side_sign)
            center = plus(box_center,scale(axes[axis],side_sign))
            lever = sub(center,com)
            u = sub(plus(linear,cross(angular,lever)),wind)
            un = dot(u,normal)
            tangential = sub(u,scale(normal,un))
            pres = scale(normal,-.5*rho*pressure*world_area*max(0.,un)**2)
            tang = scale(tangential,-.5*rho*skin*world_area*norm(tangential))
            f = plus(pres,tang)
            mag = norm(f)
            if mag == 0:
                continue
            direction = scale(f,1/mag)
            arm = cross(lever,direction)
            i_arm = tuple(x*y for x,y in zip(inv_inertia,arm))
            k = invmass+dot(arm,i_arm)
            opposing = -dot(u,direction)
            if opposing <= 0:
                continue
            impulse = scale(direction,min(mag*dt,opposing/k))
            linear = plus(linear,scale(impulse,invmass))
            ang_imp = cross(lever,impulse)
            angular = plus(angular,tuple(x*y for x,y in zip(inv_inertia,ang_imp)))
    return linear,angular


class RigidBoxPanelTests(unittest.TestCase):
    def test_stationary_body_has_zero_pressure(self):
        self.assertEqual(step((0,0,0),(0,0,0)),((0,0,0),(0,0,0)))

    def test_centered_cube_has_one_windward_panel(self):
        v,w=step((10,0,0),(0,0,0))
        self.assertAlmostEqual(v[0],8)
        self.assertEqual(v[1:],(0,0))
        self.assertEqual(w,(0,0,0))

    def test_reverse_velocity_reverses_drag(self):
        v,w=step((-10,0,0),(0,0,0))
        self.assertAlmostEqual(v[0],-8)
        self.assertEqual(w,(0,0,0))

    def test_pressure_scales_with_air_density(self):
        a,_=step((10,0,0),(0,0,0),rho=1)
        b,_=step((10,0,0),(0,0,0),rho=2)
        self.assertAlmostEqual(a[0],8)
        self.assertAlmostEqual(b[0],6)

    def test_pressure_coefficient_scales_linearly(self):
        a,_=step((10,0,0),(0,0,0),pressure=1)
        b,_=step((10,0,0),(0,0,0),pressure=2)
        self.assertAlmostEqual(a[0],8)
        self.assertAlmostEqual(b[0],6)

    def test_face_area_uses_true_affine_axes(self):
        axes=((1,0,0),(0,2,0),(0,0,3))
        v,w=step((10,0,0),(0,0,0),axes=axes,dt=.001)
        self.assertAlmostEqual(v[0],8.8)
        self.assertEqual(w,(0,0,0))

    def test_large_timestep_cannot_reverse_velocity(self):
        for dt in [.1,1.,10.,100.]:
            v,w=step((10,0,0),(0,0,0),dt=dt)
            self.assertGreaterEqual(v[0],0)
            self.assertAlmostEqual(v[0],0)
            self.assertEqual(w,(0,0,0))

    def test_wind_relative_motion_and_galilean_invariance(self):
        v1,w1=step((10,0,0),(0,0,0))
        v2,w2=step((13,2,5),(0,0,0),wind=(3,2,5))
        for a,b,shift in zip(v1,v2,(3,2,5)):
            self.assertAlmostEqual(a+shift,b)
        self.assertEqual(w1,w2)

    def test_convected_body_has_no_drag(self):
        v,w=step((4,-3,9),(0,0,0),wind=(4,-3,9))
        self.assertEqual(v,(4,-3,9))
        self.assertEqual(w,(0,0,0))

    def test_offset_box_generates_physical_torque(self):
        v,w=step((10,0,0),(0,0,0),box_center=(0,1,0))
        self.assertLess(v[0],10)
        self.assertGreater(w[2],0)
        self.assertAlmostEqual(w[0],0)

    def test_world_inertia_controls_drag_angular_acceleration(self):
        v1,w1=step((10,0,0),(0,0,0),box_center=(0,1,0))
        v2,w2=step((10,0,0),(0,0,0),box_center=(0,1,0),
                   inv_inertia=(.5,.5,.5))
        self.assertAlmostEqual(v1[0],v2[0])
        self.assertGreater(w1[2],w2[2])

    def test_pure_spin_is_damped_by_skin_and_pressure_is_inactive(self):
        v0,w0=step((0,0,0),(0,0,10),pressure=1,skin=0)
        self.assertEqual(v0,(0,0,0))
        self.assertEqual(w0,(0,0,10))
        v,w=step((0,0,0),(0,0,10),pressure=0,skin=.1)
        self.assertLess(norm(w),10)
        self.assertLess(point_energy(v,w),50)

    def test_skin_drag_on_transverse_faces_dissipates_motion(self):
        v,w=step((10,0,0),(0,0,0),pressure=0,skin=.1)
        self.assertLess(v[0],10)
        self.assertLess(point_energy(v,w),50)

    def test_reflected_and_rotated_boxes_are_consistent(self):
        mirror=((-1,0,0),(0,1,0),(0,0,1))
        rotated=((0,1,0),(-1,0,0),(0,0,1))
        a,_=step((10,0,0),(0,0,0),axes=mirror)
        b,_=step((0,10,0),(0,0,0),axes=rotated)
        self.assertAlmostEqual(a[0],8)
        self.assertAlmostEqual(b[1],8)

    def test_sheared_box_still_dissipates_energy(self):
        shear=((1,0,0),(.5,1,0),(0,0,1))
        v,w=step((10,0,0),(0,0,0),axes=shear,pressure=.5,skin=.01)
        self.assertLess(point_energy(v,w),50)

    def test_repeated_windless_face_impulses_reduce_energy(self):
        v,w=(10.,-3.,4.),(1.,-2.,5.)
        original=point_energy(v,w)
        for _ in range(25):
            old=point_energy(v,w)
            v,w=step(v,w,pressure=.5,skin=.05)
            self.assertLessEqual(point_energy(v,w),old+1e-9)
        self.assertLess(point_energy(v,w),.8*original)

    def test_project_settings_are_cached_and_safe_by_default(self):
        server=(ROOT/"servers/physics_3d/physics_server_3d.cpp").read_text()
        space=(ROOT/"modules/godot_physics_3d/godot_space_3d.cpp").read_text()
        header=(ROOT/"modules/godot_physics_3d/godot_space_3d.h").read_text()
        for suffix in ("pressure_coefficient","skin_coefficient","density","wind_velocity"):
            name="rigid_box_aero_"+suffix
            self.assertIn(f'"physics/3d/solver/{name}"',server)
            self.assertIn(f'GLOBAL_GET("physics/3d/solver/{name}")',space)
            self.assertIn(f"get_{name}()",header)
        self.assertIn("rigid_box_aero_pressure_coefficient = 0.0;",header)
        self.assertIn("rigid_box_aero_skin_coefficient = 0.0;",header)
        self.assertIn("configured_box_wind.is_finite()",space)

    def test_rigidbody_shape_transform_and_center_of_mass_wiring(self):
        body=(ROOT/"modules/godot_physics_3d/godot_body_3d.cpp").read_text()
        self.assertIn('#include "servers/physics_rigid_box_aero_panels_3d.h"',body)
        self.assertIn("mode == PS3DE::BODY_MODE_RIGID && p_step > 0.0",body)
        self.assertIn("get_space()->get_rigid_box_aero_pressure_coefficient() > 0.0",body)
        self.assertIn("get_space()->get_rigid_box_aero_skin_coefficient() > 0.0",body)
        self.assertIn("shape->get_type() != PS3DE::SHAPE_BOX",body)
        self.assertIn("if (is_shape_disabled(i))",body)
        self.assertIn("get_transform() * get_shape_transform(i)",body)
        self.assertIn("box->get_half_extents()",body)
        self.assertIn("world_com = get_transform().origin + center_of_mass",body)
        self.assertIn("_inv_mass, _inv_inertia_tensor, p_step",body)
        self.assertLess(body.index("linear_velocity = godot_physics_fluid_linear_drag("),
                        body.index("godot_physics_rigid_box_aero_step_3d("))
        self.assertLess(body.index("godot_physics_rigid_box_aero_step_3d("),
                        body.index("angular_velocity = godot_physics_clamp_angular_velocity("))

    def test_helper_transactionality_and_face_effective_mass_limit(self):
        helper=(ROOT/"servers/physics_rigid_box_aero_panels_3d.h").read_text()
        self.assertIn("for (int axis = 0; axis < 3; ++axis)",helper)
        self.assertIn("for (int side = 0; side < 2; ++side)",helper)
        self.assertIn("const real_t k = p_inverse_mass + arm.dot(inverse_rotational_arm);",helper)
        self.assertIn("const double max_impulse = double(opposing_speed) / double(k);",helper)
        self.assertIn("const double magnitude = MIN(proposed_impulse, max_impulse);",helper)
        self.assertIn("p_world_half_axes[(axis + 1) % 3].cross(",helper)
        self.assertIn("const Vector3 pressure = normal *",helper)
        self.assertIn("const Vector3 skin = tangential *",helper)
        self.assertLess(helper.index("if (!next_velocity.is_finite()") if
                        "if (!next_velocity.is_finite()" in helper else 0,
                        helper.index("r_linear_velocity = linear;"))
        self.assertIn("r_linear_velocity = linear;",helper)
        self.assertIn("r_angular_velocity = angular;",helper)
        self.assertNotIn("memnew(",helper)
        self.assertNotIn("malloc(",helper)

    def test_native_cases_and_ci(self):
        native=(ROOT/"tests/servers/test_physics_rigid_box_aero_panels_3d.cpp").read_text()
        ci=(ROOT/".github/workflows/physics-rigid-box-aero-panels.yml").read_text()
        self.assertIn("TEST_FORCE_LINK(test_physics_rigid_box_aero_panels_3d)",native)
        self.assertGreaterEqual(native.count("TEST_CASE("),23)
        self.assertIn("World inverse inertia changes offset aerodynamic torque",native)
        self.assertIn("python3 -m unittest discover",ci)


if __name__ == "__main__":
    unittest.main()
