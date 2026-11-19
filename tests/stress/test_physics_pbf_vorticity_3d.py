"""Independent reference and integration contracts for native PBF curl restoration.

These equations are implemented independently of the C++ header to
check signs, three-pass SPH curl/magnitude gradients, conservation of
purely rotational velocity directions and bounded energy injection.
"""
import math
import random
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def dot(a, b):
    return sum(x*y for x, y in zip(a, b))


def sub(a, b):
    return tuple(x-y for x, y in zip(a, b))


def add(a, b):
    return tuple(x+y for x, y in zip(a, b))


def scale(a, s):
    return tuple(x*s for x in a)


def cross(a, b):
    return (
        a[1]*b[2]-a[2]*b[1],
        a[2]*b[0]-a[0]*b[2],
        a[0]*b[1]-a[1]*b[0],
    )


def norm(a):
    return math.sqrt(dot(a,a))


def poly6(d2, h):
    if not 0 <= d2 < h*h:
        return 0.
    return 315./(64.*math.pi*h**3) * (1.-d2/(h*h))**3


def gradient(r, h):
    d2 = dot(r,r)
    if d2 <= 0 or d2 >= h*h:
        return (0.,0.,0.)
    return scale(r, -945./(32.*math.pi*h**5)*(1.-d2/(h*h))**2)


def solve_vorticity(points, velocities, h, mass=6., rest_density=1000.,
                    strength=.9, dt=1./60., cap=.12):
    """Brute-force reference, no cell lookup and no particle limit."""
    n=len(points)
    rho=[mass*sum(poly6(dot(sub(p,q),sub(p,q)),h) for q in points) for p in points]
    curls=[]
    for i in range(n):
        omega=(0.,0.,0.)
        for j in range(n):
            if i == j:
                continue
            grad=gradient(sub(points[i],points[j]),h)
            weight=mass/max(rho[j],rest_density*.1)
            omega=add(omega,scale(cross(grad,sub(velocities[j],velocities[i])),weight))
        curls.append(omega)
    corrections=[]
    for i in range(n):
        eta=(0.,0.,0.)
        for j in range(n):
            if i == j:
                continue
            grad=gradient(sub(points[i],points[j]),h)
            weight=mass/max(rho[j],rest_density*.1)
            eta=add(eta,scale(grad,weight*(norm(curls[j])-norm(curls[i]))))
        if norm(eta)<=1e-8 or norm(curls[i])<=1e-8 or not strength:
            corrections.append((0.,0.,0.))
            continue
        force=cross(scale(eta,1./norm(eta)),curls[i])
        increment=min(norm(force)*strength*dt,cap)
        corrections.append(scale(force,increment/norm(force)) if norm(force)>1e-12
                           else (0.,0.,0.))
    return rho,curls,corrections


class PBFVorticityReference(unittest.TestCase):
    def test_4000_random_curl_pair_signs_and_orthogonality(self):
        rng=random.Random(20261119)
        for _ in range(4000):
            grad=tuple(rng.uniform(-20,20) for _ in range(3))
            dv=tuple(rng.uniform(-5,5) for _ in range(3))
            weight=rng.uniform(.001,.1)
            omega=scale(cross(grad,dv),weight)
            self.assertAlmostEqual(dot(omega,dv),0.,delta=1e-10)
            self.assertAlmostEqual(dot(omega,grad),0.,delta=1e-10)
            self.assertEqual(omega,scale(cross(dv,grad),-weight))

    def test_uniform_translation_has_zero_vorticity(self):
        points=[(x*.18,y*.18,z*.18) for x in range(-2,3)
                for y in range(-2,3) for z in range(-2,3)]
        velocities=[(1.2,-3.4,0.9)]*len(points)
        rho,curls,delta=solve_vorticity(points,velocities,.42)
        self.assertTrue(all(norm(w)==0. for w in curls))
        self.assertTrue(all(norm(v)==0. for v in delta))
        self.assertTrue(all(d>0 for d in rho))

    def test_solid_rotation_has_positive_correct_curl_sign(self):
        points=[(x*.16,y*.16,z*.16) for x in range(-3,4)
                for y in range(-3,4) for z in range(-3,4)]
        clockwise=[(-p[1],p[0],0.) for p in points]
        anticlockwise=[(p[1],-p[0],0.) for p in points]
        _,omega_cw,_=solve_vorticity(points,clockwise,.42)
        _,omega_ccw,_=solve_vorticity(points,anticlockwise,.42)
        center=points.index((0.,0.,0.))
        self.assertGreater(omega_cw[center][2],1.)
        self.assertLess(omega_ccw[center][2],-1.)
        self.assertAlmostEqual(omega_cw[center][2],-omega_ccw[center][2],delta=1e-12)

    def test_compact_gaussian_swirl_has_inward_gradient_and_tangential_restore(self):
        points=[(x*.16,y*.16,z*.16) for x in range(-3,4)
                for y in range(-3,4) for z in range(-3,4)]
        vel=[(-p[1]*math.exp(-6*dot(p,p)),p[0]*math.exp(-6*dot(p,p)),0.)
             for p in points]
        rho,omega,dv=solve_vorticity(points,vel,.42)
        at_right=points.index((.16,0.,0.))
        self.assertGreater(omega[at_right][2],.5)
        self.assertGreater(dv[at_right][1],0.)
        self.assertAlmostEqual(dot(dv[at_right],omega[at_right]),0.,delta=1e-10)
        self.assertTrue(all(norm(v)<=.12+1e-12 for v in dv))

    def test_large_curl_stays_capped_and_finite(self):
        rng=random.Random(20261119)
        for _ in range(1000):
            eta=tuple(rng.uniform(-10,10) for _ in range(3))
            omega=tuple(rng.uniform(-1e7,1e7) for _ in range(3))
            cap=rng.uniform(.001,2.)
            if norm(eta)<1e-10 or norm(omega)<1e-10:
                continue
            force=cross(scale(eta,1./norm(eta)),omega)
            corrected=scale(force,min(norm(force)*5.*.1,cap)/norm(force))
            self.assertTrue(all(math.isfinite(x) for x in corrected))
            self.assertLessEqual(norm(corrected),cap+1e-10)
            self.assertAlmostEqual(dot(corrected,eta),0.,delta=1e-7)
            self.assertAlmostEqual(dot(corrected,omega),0.,delta=1e-3)

    def test_simple_shear_produces_nonzero_bounded_updates(self):
        points=[(x*.19,y*.19,z*.19) for x in range(-2,3)
                for y in range(-2,3) for z in range(-2,3)]
        def pulse(point, center, velocity):
            distance2=dot(sub(point,center),sub(point,center))
            weight=max(0.,1.-distance2)**2
            return scale(velocity,weight)
        vel=[add(pulse(p,(-.25,0.,0.),(0.,0.,4.)),
                 pulse(p,(.25,0.,0.),(0.,0.,-4.))) for p in points]
        _,omega,delta=solve_vorticity(points,vel,.42)
        self.assertGreater(sum(norm(w) for w in omega)/len(omega),1.)
        self.assertGreater(sum(norm(v)>1e-6 for v in delta),50)
        self.assertLessEqual(max(map(norm,delta)),.12+1e-12)

    def test_native_source_implements_three_passes_and_default_off(self):
        header=(ROOT/"scene/3d/physics/pbf_particle_fluid_3d.h").read_text()
        source=(ROOT/"scene/3d/physics/pbf_particle_fluid_3d.cpp").read_text()
        helper=(ROOT/"servers/physics_pbf_vorticity_3d.h").read_text()
        self.assertIn("vorticity_confinement = 0.0",header)
        self.assertIn("vorticity_max_velocity_change = 0.12",header)
        self.assertIn("Vector<Vector3> vorticities;",header)
        self.assertIn("Vector<Vector3> confinement_updates;",header)
        self.assertIn("vorticities.resize(p_count);",source)
        self.assertIn("confinement_updates.resize(p_count);",source)
        self.assertIn("if (!(vorticity_confinement > 0.0))",source)
        self.assertIn("PhysicsPBFVorticity3D::curl_pair(",source)
        self.assertIn("PhysicsPBFVorticity3D::magnitude_gradient_pair(",source)
        self.assertIn("PhysicsPBFVorticity3D::velocity_increment(",source)
        self.assertIn("_apply_vorticity_confinement(p_delta);",source)
        self.assertIn("p_kernel_gradient.cross(p_neighbor_velocity_difference)",helper)
        self.assertIn("unit_eta.cross(p_vorticity)",helper)
        self.assertIn("MIN(unbounded_increment, double(p_max_increment))",helper)
        self.assertNotIn("memalloc",helper)
        self.assertIn("last_vorticity_neighbor_evaluations",source)

    def test_native_ci_and_lab_registration(self):
        cpp=(ROOT/"tests/servers/test_physics_pbf_vorticity_3d.cpp").read_text()
        scene=(ROOT/"tests/stress/physics_pbf_vorticity_3d_regression.gd").read_text()
        workflow=(ROOT/".github/workflows/physics-pbf-vorticity.yml").read_text()
        lab=(ROOT/"demo/physics_lab/pbf_water_3d.gd").read_text()
        docs=(ROOT/"doc/classes/PBFParticleFluid3D.xml").read_text()
        self.assertEqual(cpp.count('TEST_CASE("[PhysicsPBFVorticity]'),7)
        self.assertIn("TEST_FORCE_LINK(test_physics_pbf_vorticity_3d)",cpp)
        self.assertIn("vorticity_confinement",scene)
        self.assertIn("get_last_vorticity_neighbor_evaluations",scene)
        self.assertIn("test_physics_pbf_vorticity_compiler.cpp",workflow)
        self.assertIn("KEY_V:",lab)
        self.assertIn('name="vorticity_confinement"',docs)
        self.assertIn('name="vorticity_max_velocity_change"',docs)


if __name__=="__main__":
    unittest.main()
