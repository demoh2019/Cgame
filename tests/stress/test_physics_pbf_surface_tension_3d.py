"""Independent SPH surface tension reference for the Cgame PBF solver.

The reference is deliberately brute-force all-pairs, not the production
sorted-cell neighbor grid, to check pair momentum, curvature sign,
cohesion kernel and numerical caps independently of native C++.
"""
import math
import random
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def sub(a, b):
    return tuple(x-y for x, y in zip(a,b))


def add(a, b):
    return tuple(x+y for x, y in zip(a,b))


def scale(a, value):
    return tuple(x*value for x in a)


def dot(a, b):
    return sum(x*y for x,y in zip(a,b))


def norm(a):
    return math.sqrt(dot(a,a))


def grad_poly6(r,h):
    d2=dot(r,r)
    if not 0 < d2 < h*h:
        return (0.,0.,0.)
    factor=-945./(32.*math.pi*h**5)*(1.-d2/h**2)**2
    return scale(r,factor)


def poly6(d2,h):
    if not 0 <= d2 < h*h:
        return 0.
    return 315./(64.*math.pi*h**3)*(1.-d2/h**2)**3


def cohesion_kernel(r,h):
    if not 1e-8 < r < h:
        return 0.
    r3=r**3
    d3=(h-r)**3
    shape=(2*d3*r3-h**6/64) if r<=h/2 else (d3*r3)
    return 32./(math.pi*h**9)*shape


def paired_increment(displacement, n1, n2, rho1, rho2, rest, mass,
                     h, cohesion, curvature, dt, cap):
    r=norm(displacement)
    if not 1e-8 < r < h or not cohesion+curvature:
        return (0.,0.,0.)
    weight=min(4.,2*rest/(rho1+rho2))
    radial=scale(displacement,1/r)
    acceleration=scale(add(scale(radial,mass*cohesion_kernel(r,h)*cohesion),
                           scale(sub(n1,n2),curvature)),-weight)
    length=norm(acceleration)
    return scale(acceleration,min(length*dt,cap)/length) if length else (0.,0.,0.)


def solve_surface(points, h=.42, mass=6., rest=1000.,
                  cohesion=.06,curvature=.025,dt=1./60.,cap=.005):
    n=len(points)
    rho=[sum(mass*poly6(dot(sub(p,q),sub(p,q)),h) for q in points)
         for p in points]
    normals=[]
    for i in range(n):
        ni=(0.,0.,0.)
        for j in range(n):
            if i==j:
                continue
            grad=grad_poly6(sub(points[i],points[j]),h)
            ni=add(ni,scale(grad,h*mass/max(rho[j],rest*.1)))
        normals.append(ni)
    increments=[(0.,0.,0.) for _ in range(n)]
    pairs=0
    for i in range(n):
        for j in range(i+1,n):
            dv=paired_increment(sub(points[i],points[j]),normals[i],normals[j],
                                rho[i],rho[j],rest,mass,h,
                                cohesion,curvature,dt,cap)
            if norm(dv)>0:
                increments[i]=add(increments[i],dv)
                increments[j]=sub(increments[j],dv)
                pairs+=1
    return increments,normals,rho,pairs


class PBFSurfaceTensionReference(unittest.TestCase):
    def test_3000_random_kernel_values_and_symmetry(self):
        rng=random.Random(20261119)
        for _ in range(3000):
            h=rng.uniform(.08,2)
            r=rng.uniform(.01*h,.99*h)
            c=cohesion_kernel(r,h)
            self.assertTrue(math.isfinite(c))
            self.assertAlmostEqual(cohesion_kernel(r,h),
                                   cohesion_kernel(-r,h) if r<=0 else c)
            self.assertEqual(cohesion_kernel(h,h),0)
        self.assertLess(cohesion_kernel(.05*.42,.42),0)
        self.assertGreater(cohesion_kernel(.7*.42,.42),0)

    def test_two_particle_attraction_and_close_range_repulsion(self):
        for r,expect in ((.29,1),(.015,-1)):
            left=paired_increment((-r,0.,0.),(0.,0.,0.),(0.,0.,0.),
                                  1000.,1000.,1000.,6.,.42,.1,0.,.016,.01)
            self.assertGreater(left[0]*expect,0.)
            right=paired_increment((r,0.,0.),(0.,0.,0.),(0.,0.,0.),
                                   1000.,1000.,1000.,6.,.42,.1,0.,.016,.01)
            self.assertAlmostEqual(left[0],-right[0],delta=1e-14)

    def test_curvature_smoothing_is_equal_opposite(self):
        dv=paired_increment((.2,0,0),(0,1,0),(0,-1,0),
                            1000.,1000.,1000.,6.,.42,0.,.5,.016,.05)
        self.assertLess(dv[1],0.)
        self.assertEqual(dv[0],0.)
        other=paired_increment((-.2,0,0),(0,-1,0),(0,1,0),
                               1000.,1000.,1000.,6.,.42,0.,.5,.016,.05)
        self.assertEqual(other,scale(dv,-1.))

    def test_3000_random_pairs_have_zero_net_impulse_and_cap(self):
        rng=random.Random(69)
        for _ in range(3000):
            distance=rng.uniform(.001,.41)
            disp=(-distance,0.,0.)
            ni=tuple(rng.uniform(-2,2) for _ in range(3))
            nj=tuple(rng.uniform(-2,2) for _ in range(3))
            r1=rng.uniform(200,2000)
            r2=rng.uniform(200,2000)
            coh=rng.uniform(0,2)
            curv=rng.uniform(0,2)
            cap=rng.uniform(.0001,.05)
            args=(r1,r2,1000.,6.,.42,coh,curv,.016,cap)
            d1=paired_increment(disp,ni,nj,*args)
            d2=paired_increment(scale(disp,-1),nj,ni,r2,r1,1000.,6.,.42,
                                coh,curv,.016,cap)
            self.assertLess(norm(add(d1,d2)),1e-12)
            self.assertLessEqual(norm(d1),cap+1e-12)

    def test_surface_of_static_cloud_has_nonzero_normals_and_paired_forces(self):
        points=[(x*.19,y*.19,z*.19) for x in range(-2,3)
                for y in range(-2,3) for z in range(-2,3)]
        d,n,rho,pairs=solve_surface(points)
        self.assertGreater(pairs,150)
        self.assertGreater(max(map(norm,n)),.1)
        self.assertTrue(all(math.isfinite(x) for p in d for x in p))
        self.assertGreater(sum(norm(p) for p in d),.01)
        self.assertLess(norm(tuple(sum(v[k] for v in d)
                                   for k in range(3))),1e-10)
        self.assertGreater(min(rho),0.)

    def test_random_125_cloud_and_momentum_conservation(self):
        rng=random.Random(117)
        points=[(x*.18+rng.uniform(-.018,.018),
                 y*.18+rng.uniform(-.018,.018),
                 z*.18+rng.uniform(-.018,.018))
                for x in range(5) for y in range(5) for z in range(5)]
        d,_,_,pairs=solve_surface(points,cap=.003)
        self.assertGreater(pairs,200)
        self.assertLess(max(map(norm,d)),.4)
        self.assertLess(norm(tuple(sum(v[k] for v in d)
                                   for k in range(3))),1e-10)

    def test_disabled_default_baseline_and_invalid_source_contracts(self):
        h=(ROOT/"scene/3d/physics/pbf_particle_fluid_3d.h").read_text()
        s=(ROOT/"scene/3d/physics/pbf_particle_fluid_3d.cpp").read_text()
        helper=(ROOT/"servers/physics_pbf_surface_tension_3d.h").read_text()
        self.assertIn("surface_cohesion = 0.0",h)
        self.assertIn("surface_curvature = 0.0",h)
        self.assertIn("_sync_surface_tension_buffers();",s)
        self.assertIn("surface_tension_velocity_changes.resize(count);",s)
        self.assertIn("surface_tension_velocity_changes.clear();",s)
        self.assertIn("p_j <= i",s)
        self.assertIn("corrections_ptr[p_j] -= dv;",s)
        self.assertIn("_apply_surface_tension(p_delta);",s)
        self.assertIn("cohesion_kernel(distance, p_h)",helper)
        self.assertIn("p_normal_i - p_normal_j",helper)

    def test_native_ci_lab_and_stress_registration(self):
        cpp=(ROOT/"tests/servers/test_physics_pbf_surface_tension_3d.cpp").read_text()
        scene=(ROOT/"tests/stress/physics_pbf_surface_tension_3d_regression.gd").read_text()
        wf=(ROOT/".github/workflows/physics-pbf-surface-tension.yml").read_text()
        lab=(ROOT/"demo/physics_lab/pbf_water_3d.gd").read_text()
        docs=(ROOT/"doc/classes/PBFParticleFluid3D.xml").read_text()
        runner=(ROOT/"tests/stress/stress.gd").read_text()
        self.assertEqual(cpp.count('TEST_CASE("[PhysicsPBFSurface]'),8)
        self.assertIn("TEST_FORCE_LINK(test_physics_pbf_surface_tension_3d)",cpp)
        self.assertIn("get_last_surface_tension_pairs()",scene)
        self.assertIn("test_physics_pbf_surface_tension_compiler.cpp",wf)
        self.assertIn("KEY_J:",lab)
        self.assertIn('name="surface_cohesion"',docs)
        self.assertIn('name="surface_curvature"',docs)
        self.assertIn('"physics_pbf_surface_3d_enabled"',runner)
        self.assertIn('"physics_pbf_surface_3d_disabled"',runner)


if __name__ == "__main__":
    unittest.main()
