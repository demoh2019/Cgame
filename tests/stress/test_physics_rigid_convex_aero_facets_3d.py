"""Independent facet aerodynamics numerical oracle and GodotPhysics3D contracts."""

from __future__ import annotations

import math
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


def add(a,b):
    return tuple(x+y for x,y in zip(a,b))


def sub(a,b):
    return tuple(x-y for x,y in zip(a,b))


def mul(a,s):
    return tuple(x*s for x in a)


def dot(a,b):
    return sum(x*y for x,y in zip(a,b))


def cross(a,b):
    return (a[1]*b[2]-a[2]*b[1],
            a[2]*b[0]-a[0]*b[2],
            a[0]*b[1]-a[1]*b[0])


def norm(a):
    return math.sqrt(dot(a,a))


BOX_VERTICES=(
    (-1.,-1.,-1.),(1.,-1.,-1.),(1.,1.,-1.),(-1.,1.,-1.),
    (-1.,-1.,1.),(1.,-1.,1.),(1.,1.,1.),(-1.,1.,1.))
BOX_FACES=(
    (0,1,2,3),(4,7,6,5),(0,4,5,1),
    (3,2,6,7),(0,3,7,4),(1,5,6,2))
TETRA_VERTICES=((-1,-1,-1),(1,-1,-1),(-1,1,-1),(-1,-1,1))
TETRA_FACES=((0,1,2),(0,3,1),(0,2,3),(1,3,2))


def transform(p,axes=None,shift=(0,0,0)):
    if axes is None:
        return add(p,shift)
    return add(add(add(mul(axes[0],p[0]),mul(axes[1],p[1])),
                   mul(axes[2],p[2])),shift)


def facet(vertices,face,axes=None,shift=(0,0,0)):
    """Triangle fan area and area-weighted center; orient with hull interior."""
    world=[transform(p,axes,shift) for p in vertices]
    interior=mul(tuple(sum(p[j] for p in world) for j in range(3)),
                 1/len(world))
    a=world[face[0]]
    total=0.
    summed_normal=(0.,0.,0.)
    first_moment=(0.,0.,0.)
    for i in range(1,len(face)-1):
        b,c=world[face[i]],world[face[i+1]]
        ct=cross(sub(b,a),sub(c,a))
        area=.5*norm(ct)
        if area==0:
            continue
        center=mul(add(add(a,b),c),1/3)
        first_moment=add(first_moment,mul(center,area))
        summed_normal=add(summed_normal,ct)
        total+=area
    if total<=0 or norm(summed_normal)==0:
        raise ValueError("degenerate polygon")
    center=mul(first_moment,1/total)
    sign=1 if dot(summed_normal,sub(center,interior))>0 else -1
    normal=mul(summed_normal,sign/norm(summed_normal))
    return center,normal,total


def integrate(vertices,faces,v,omega=(0,0,0),axes=None,shift=(0,0,0),
              com=(0,0,0),wind=(0,0,0),density=1,pressure=1,skin=0,
              dt=.01,imass=1,inv_inertia=(1,1,1)):
    """Independent point-impulse, directional-mass, Gauss-Seidel panel model."""
    linear,angular=tuple(v),tuple(omega)
    for f in faces:
        c,n,area=facet(vertices,f,axes,shift)
        lever=sub(c,com)
        relative=sub(add(linear,cross(angular,lever)),wind)
        ns=dot(relative,n)
        tangent=sub(relative,mul(n,ns))
        fp=mul(n,-.5*density*pressure*area*max(ns,0)**2)
        fs=mul(tangent,-.5*density*skin*area*norm(tangent))
        force=add(fp,fs)
        force_length=norm(force)
        if not force_length:
            continue
        direction=mul(force,1/force_length)
        arm=cross(lever,direction)
        rotated=tuple(x*y for x,y in zip(arm,inv_inertia))
        k=imass+dot(arm,rotated)
        opposing=-dot(relative,direction)
        if opposing<=0:
            continue
        impulse=mul(direction,min(force_length*dt,opposing/k))
        linear=add(linear,mul(impulse,imass))
        ang_imp=cross(lever,impulse)
        angular=add(angular,tuple(x*y for x,y in zip(ang_imp,inv_inertia)))
    return linear,angular


def kinetic(v,w):
    return .5*(dot(v,v)+dot(w,w))


class ConvexFacetAnalyticalTests(unittest.TestCase):
    def test_true_box_polygon_center_area_and_normal(self):
        c,n,area=facet(BOX_VERTICES,BOX_FACES[5])
        self.assertEqual(c,(1.,0.,0.))
        self.assertEqual(n,(1.,0.,0.))
        self.assertEqual(area,4.)

    def test_polygon_winding_reversal(self):
        a=facet(BOX_VERTICES,BOX_FACES[5])
        b=facet(BOX_VERTICES,tuple(reversed(BOX_FACES[5])))
        self.assertEqual(a,b)

    def test_uniform_translation_does_not_change_normals_or_area(self):
        c,n,a=facet(BOX_VERTICES,BOX_FACES[5])
        shifted,normal,area=facet(BOX_VERTICES,BOX_FACES[5],
                                 shift=(100,200,-300))
        self.assertEqual(shifted,add(c,(100,200,-300)))
        self.assertEqual(n,normal)
        self.assertEqual(a,area)

    def test_nonuniform_scale_uses_true_area_and_center(self):
        axes=((2,0,0),(0,3,0),(0,0,4))
        c,n,area=facet(BOX_VERTICES,BOX_FACES[5],axes,shift=(10,20,30))
        self.assertEqual(c,(12,20,30))
        self.assertEqual(n,(1.,0.,0.))
        self.assertEqual(area,48)

    def test_mirrored_winding_still_points_outward(self):
        axes=((-2,0,0),(0,3,0),(0,0,4))
        c,n,area=facet(BOX_VERTICES,BOX_FACES[5],axes)
        self.assertEqual(c,(-2,0,0))
        self.assertEqual(n,(-1.,0.,0.))
        self.assertEqual(area,48)

    def test_analytic_cube_windward_drag(self):
        v,w=integrate(BOX_VERTICES,BOX_FACES,(10,0,0))
        self.assertAlmostEqual(v[0],8,places=12)
        self.assertAlmostEqual(norm(w),0,places=12)

    def test_reversal_changes_pressure_face(self):
        v,w=integrate(BOX_VERTICES,BOX_FACES,(-10,0,0))
        self.assertAlmostEqual(v[0],-8)
        self.assertAlmostEqual(norm(w),0)

    def test_density_and_drag_coeff_scale_force(self):
        one,_=integrate(BOX_VERTICES,BOX_FACES,(10,0,0))
        two,_=integrate(BOX_VERTICES,BOX_FACES,(10,0,0),density=2)
        twice_cp,_=integrate(BOX_VERTICES,BOX_FACES,(10,0,0),pressure=2)
        self.assertAlmostEqual(one[0],8)
        self.assertAlmostEqual(two[0],6)
        self.assertAlmostEqual(twice_cp[0],6)

    def test_rectangular_hull_area_scaling(self):
        axes=((2,0,0),(0,3,0),(0,0,4))
        v,w=integrate(BOX_VERTICES,BOX_FACES,(10,0,0),axes=axes,dt=.001)
        self.assertAlmostEqual(v[0],7.6)
        self.assertAlmostEqual(norm(w),0)

    def test_limiter_prevents_large_step_reversal(self):
        for dt in (.1,1,10,100):
            v,w=integrate(BOX_VERTICES,BOX_FACES,(10,0,0),dt=dt)
            self.assertAlmostEqual(v[0],0)
            self.assertGreaterEqual(v[0],0)
            self.assertAlmostEqual(norm(w),0)

    def test_medium_translation_is_galilean_invariant(self):
        base,_=integrate(BOX_VERTICES,BOX_FACES,(10,0,0))
        moved,_=integrate(BOX_VERTICES,BOX_FACES,(13,2,5),wind=(3,2,5))
        self.assertEqual(moved,add(base,(3,2,5)))

    def test_zero_flow_when_body_moves_with_wind(self):
        v,w=integrate(BOX_VERTICES,BOX_FACES,(4,2,-5),
                      wind=(4,2,-5),skin=1)
        self.assertEqual(v,(4,2,-5))
        self.assertEqual(w,(0,0,0))

    def test_compound_offset_hull_produces_torque(self):
        v,w=integrate(BOX_VERTICES,BOX_FACES,(10,0,0),
                      shift=(0,1,0))
        self.assertLess(v[0],10)
        self.assertGreater(w[2],0)

    def test_pure_spin_damps_via_skin_friction(self):
        v,w=integrate(BOX_VERTICES,BOX_FACES,(0,0,0),(0,0,10),
                      pressure=0,skin=.1)
        self.assertLess(kinetic(v,w),50)
        self.assertLess(abs(w[2]),10)

    def test_energy_dissipates_over_many_steps(self):
        v,w=(10,-3,4),(1,-2,5)
        initial=kinetic(v,w)
        for _ in range(30):
            previous=kinetic(v,w)
            v,w=integrate(BOX_VERTICES,BOX_FACES,v,w,
                          pressure=.5,skin=.05)
            self.assertLessEqual(kinetic(v,w),previous+1e-9)
        self.assertLess(kinetic(v,w),initial)

    def test_nonbox_tetrahedron_dissipates_energy(self):
        v,w=integrate(TETRA_VERTICES,TETRA_FACES,(10,0,0),
                      pressure=.5,skin=.05)
        self.assertTrue(all(math.isfinite(x) for x in v+w))
        self.assertLess(kinetic(v,w),50)

    def test_projectsettings_registration_and_default_off(self):
        server=(ROOT/"servers/physics_3d/physics_server_3d.cpp").read_text()
        space=(ROOT/"modules/godot_physics_3d/godot_space_3d.cpp").read_text()
        header=(ROOT/"modules/godot_physics_3d/godot_space_3d.h").read_text()
        for setting in ["pressure_coefficient","skin_coefficient",
                        "density","wind_velocity"]:
            token="rigid_convex_aero_"+setting
            self.assertIn(f'"physics/3d/solver/{token}"',server)
            self.assertIn(f'GLOBAL_GET("physics/3d/solver/{token}")',space)
            self.assertIn(f"get_{token}()",header)
        self.assertIn("rigid_convex_aero_pressure_coefficient = 0.0;",header)
        self.assertIn("rigid_convex_aero_skin_coefficient = 0.0;",header)
        self.assertIn("configured_convex_wind.is_finite()",space)

    def test_integrator_only_convex_and_dynamic_not_kinematic(self):
        body=(ROOT/"modules/godot_physics_3d/godot_body_3d.cpp").read_text()
        self.assertIn('#include "servers/physics_rigid_convex_aero_facets_3d.h"',body)
        self.assertIn("mode == PS3DE::BODY_MODE_RIGID && p_step > 0.0",body)
        self.assertIn("get_space()->get_rigid_convex_aero_pressure_coefficient() > 0.0",body)
        self.assertIn("shape->get_type() != PS3DE::SHAPE_CONVEX_POLYGON",body)
        self.assertIn("if (is_shape_disabled(i))",body)
        self.assertIn("convex->get_mesh()",body)
        self.assertIn("get_transform() * get_shape_transform(i)",body)
        self.assertIn("const Vector3 world_com = get_transform().origin + center_of_mass;",body)
        self.assertIn("_inv_mass, _inv_inertia_tensor, p_step",body)
        self.assertLess(body.index("linear_velocity = godot_physics_fluid_linear_drag("),
                        body.index("godot_physics_rigid_convex_aero_step_3d("))
        self.assertLess(body.index("godot_physics_rigid_convex_aero_step_3d("),
                        body.index("angular_velocity = godot_physics_clamp_angular_velocity("))

    def test_inertia_aware_transactional_point_impulses(self):
        helper=(ROOT/"servers/physics_rigid_convex_aero_facets_3d.h").read_text()
        self.assertIn("const real_t k = p_inv_mass + arm.dot(inverse_arm);",helper)
        self.assertIn("const double maximal = double(opposing_speed) / double(k);",helper)
        self.assertIn("const double amount = MIN(proposed, maximal);",helper)
        self.assertIn("p_inv_inertia_world.xform(lever.cross(impulse))",helper)
        self.assertIn("r_linear_velocity = linear;",helper)
        self.assertIn("r_angular_velocity = angular;",helper)
        self.assertIn("const uint32_t faces = p_mesh.faces.size();",helper)
        self.assertIn("faces > 256",helper)
        self.assertIn("p_world.xform(p_mesh.vertices[p_face.indices[i]])",helper)
        self.assertNotIn("memnew(",helper)
        self.assertNotIn("malloc(",helper)

    def test_native_contracts_and_workflow_present(self):
        tests=(ROOT/"tests/servers/test_physics_rigid_convex_aero_facets_3d.cpp").read_text()
        yml=(ROOT/".github/workflows/physics-rigid-convex-aero-facets.yml").read_text()
        self.assertIn("TEST_FORCE_LINK(test_physics_rigid_convex_aero_facets_3d)",tests)
        self.assertGreaterEqual(tests.count("TEST_CASE("),21)
        self.assertIn("Nonuniform stretch computes real",tests)
        self.assertIn("python3 -m unittest discover",yml)


if __name__=="__main__":
    unittest.main()
