"""Independent reference for paired PBF particle / rigid body collision impulses.

This validates the true normal effective mass including rotational inertia,
and conserves *pairwise* linear/angular momentum. It is not a substitute for
Godot native runtime checking or a full fluid-solid pressure boundary solver.
"""
import math
import random
import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]


def dot(a,b):
    return sum(x*y for x,y in zip(a,b))


def cross(a,b):
    return (a[1]*b[2]-a[2]*b[1],
            a[2]*b[0]-a[0]*b[2],
            a[0]*b[1]-a[1]*b[0])


def add(a,b):
    return tuple(x+y for x,y in zip(a,b))


def sub(a,b):
    return tuple(x-y for x,y in zip(a,b))


def scale(a,s):
    return tuple(x*s for x in a)


def coupling(p_velocity,particle_mass,body_contact_velocity,body_inverse_mass,
             inverse_inertia,lever,normal,restitution,impulse_limit):
    if any(not math.isfinite(t) for t in (
            *p_velocity,*body_contact_velocity,*lever,*normal,
            particle_mass,body_inverse_mass,inverse_inertia,restitution,impulse_limit)):
        return None
    if not 0 <= restitution <= 1 or particle_mass <= 0 or body_inverse_mass <= 0 or impulse_limit <= 0:
        return None
    nn=math.sqrt(dot(normal,normal))
    if nn <= 1e-8:
        return None
    n=scale(normal,1/nn)
    closing=dot(sub(p_velocity,body_contact_velocity),n)
    if closing >= 0:
        return None
    invmass=1/particle_mass+body_inverse_mass + max(0.,inverse_inertia*dot(cross(lever,n),cross(lever,n)))
    magnitude=min(-(1+restitution)*closing/invmass,impulse_limit)
    impulse=scale(n,magnitude)
    return add(p_velocity,scale(impulse,1/particle_mass)),scale(impulse,-1),magnitude


class PBFRigidCouplingReference(unittest.TestCase):
    def test_5000_random_impact_conservation_and_restitution(self):
        rng=random.Random(20261119)
        for i in range(5000):
            m=rng.uniform(.03,20)
            mb=rng.uniform(.1,50)
            inv_i=rng.uniform(.001,2)
            lever=tuple(rng.uniform(-3,3) for _ in range(3))
            n=tuple(rng.uniform(-2,2) for _ in range(3))
            norm=math.sqrt(dot(n,n))
            n=scale(n,1/norm)
            linear=tuple(rng.uniform(-5,5) for _ in range(3))
            spin=tuple(rng.uniform(-5,5) for _ in range(3))
            vcontact=add(linear,cross(spin,lever))
            pvel=add(vcontact,scale(n,-rng.uniform(.01,12)))
            restitution=rng.uniform(0,1)
            limit=10000.
            new= coupling(pvel,m,vcontact,1/mb,inv_i,lever,n,restitution,limit)
            self.assertIsNotNone(new)
            new_vp,body_impulse,j=new
            dvbody=scale(body_impulse,1/mb)
            dwbody=scale(cross(lever,body_impulse),inv_i)
            new_vcontact=add(add(linear,dvbody),cross(add(spin,dwbody),lever))
            before_speed=dot(sub(pvel,vcontact),n)
            after_speed=dot(sub(new_vp,new_vcontact),n)
            self.assertAlmostEqual(after_speed,-restitution*before_speed,delta=2e-11)
            particle_delta=scale(sub(new_vp,pvel),m)
            self.assertLess(math.sqrt(dot(add(particle_delta,body_impulse),
                                          add(particle_delta,body_impulse))),1e-11)
            angular_delta=add(cross(lever,particle_delta),cross(lever,body_impulse))
            self.assertLess(math.sqrt(dot(angular_delta,angular_delta)),1e-10)
            # Direct impact energy is non-increasing for a free rigid body.
            def kinetic(p,b,w):
                return .5*m*dot(p,p)+.5*mb*dot(b,b)+.5/inv_i*dot(w,w)
            initial=kinetic(pvel,linear,spin)
            final=kinetic(new_vp,add(linear,dvbody),add(spin,dwbody))
            self.assertLessEqual(final-initial,2e-10)

    def test_capped_pair_impulse_is_equal_and_opposite(self):
        new=coupling((0.,-100.,0.),3.,(0.,0.,0.),.5,.2,(1.,0.,0.),
                     (0.,1.,0.),1.,2.)
        self.assertIsNotNone(new)
        vp,ji,jmag=new
        self.assertAlmostEqual(jmag,2.)
        self.assertAlmostEqual(vp[1],-100+2/3)
        self.assertEqual(ji,(0.,-2.,0.))

    def test_separating_and_invalid_inputs_never_apply_impulse(self):
        self.assertIsNone(coupling((0.,1.,0.),1.,(0.,0.,0.),1.,1.,
                                   (0.,0.,0.),(0.,1.,0.),.1,10.))
        self.assertIsNone(coupling((0.,-1.,0.),1.,(0.,0.,0.),0.,1.,
                                   (0.,0.,0.),(0.,1.,0.),.1,10.))
        self.assertIsNone(coupling((0.,-1.,0.),1.,(0.,0.,0.),1.,1.,
                                   (0.,0.,0.),(0.,0.,0.),.1,10.))
        self.assertIsNone(coupling((0.,-1.,0.),1.,(0.,0.,0.),1.,1.,
                                   (0.,0.,0.),(0.,1.,0.),1.1,10.))

    def test_native_physics_world_wiring_and_safety_caps(self):
        helper=(ROOT/"servers/physics_pbf_rigid_coupling_3d.h").read_text()
        cpp=(ROOT/"scene/3d/physics/pbf_particle_fluid_3d.cpp").read_text()
        hdr=(ROOT/"scene/3d/physics/pbf_particle_fluid_3d.h").read_text()
        self.assertIn("p_world_inverse_inertia.xform(rxn)",helper)
        self.assertIn("inertia_response.cross(p_lever)",helper)
        self.assertIn("p_particle_velocity + impulse / p_particle_mass",helper)
        self.assertIn("r_result.body_impulse = -impulse;",helper)
        self.assertIn("MIN(unconstrained_impulse, double(p_max_impulse))",helper)
        self.assertIn("body_get_direct_state(hit.rid)",cpp)
        self.assertIn("get_inverse_inertia_tensor()",cpp)
        self.assertIn("get_center_of_mass_local()",cpp)
        self.assertIn("get_angular_velocity().cross(lever)",cpp)
        self.assertIn("rigid_state->apply_impulse(paired_impact.body_impulse",cpp)
        self.assertIn("last_rigid_impulses",hdr)
        self.assertIn("two_way_rigid_coupling = false",hdr)
        self.assertIn("max_rigid_impulse = 20.0",hdr)
        self.assertIn("PS3DE::BODY_MODE_RIGID",cpp)

    def test_native_and_engine_integration_tests_registered(self):
        native=(ROOT/"tests/servers/test_physics_pbf_rigid_coupling_3d.cpp").read_text()
        self.assertEqual(native.count('TEST_CASE("[PhysicsPBFContact]'),8)
        self.assertIn("TEST_FORCE_LINK(test_physics_pbf_rigid_coupling_3d)",native)
        ci=(ROOT/".github/workflows/whole-engine-stress.yml").read_text()
        self.assertIn("*[PhysicsPBFContact]*",ci)
        runtime=(ROOT/"tests/stress/physics_pbf_rigid_coupling_3d_regression.gd").read_text()
        self.assertIn("two_way_rigid_coupling",runtime)
        self.assertIn("body_get_state",runtime)


if __name__=="__main__":
    unittest.main()
