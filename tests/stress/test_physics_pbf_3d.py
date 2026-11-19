"""Independent Python contracts for Cgame's native CPU PBF liquid node.

Reference SPH/PBF density and its gradient are implemented from the
integral definition rather than calling C++ sources. All geometry tests
are deterministic and use the Python standard library only.
"""
import bisect
import math
import random
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def kernel_squared(d2, h):
    if d2 < 0 or d2 >= h*h:
        return 0.
    q2=d2/(h*h)
    return 315/(64*math.pi*h**3)*(1-q2)**3


def gradient(dx, h):
    r2=sum(x*x for x in dx)
    if r2 <= 0 or r2 >= h*h:
        return (0.,0.,0.)
    factor=-945/(32*math.pi*h**5)*(1-r2/(h*h))**2
    return tuple(x*factor for x in dx)


def dot(a,b):
    return sum(x*y for x,y in zip(a,b))


def pairs_bruteforce(points,h):
    h2=h*h
    return {(i,j) for i, a in enumerate(points)
            for j,b in enumerate(points)
            if j != i and sum((x-y)**2 for x,y in zip(a,b)) < h2}


def pairs_grid(points,h):
    cells=sorted((int(math.floor(p[0]/h)),int(math.floor(p[1]/h)),
                  int(math.floor(p[2]/h)),i) for i,p in enumerate(points))
    keys=[entry[:3] for entry in cells]
    pairs=set()
    for i,p in enumerate(points):
        cell=tuple(int(math.floor(x/h)) for x in p)
        for dx in (-1,0,1):
            for dy in (-1,0,1):
                for dz in (-1,0,1):
                    neighbor=(cell[0]+dx,cell[1]+dy,cell[2]+dz)
                    start=bisect.bisect_left(keys,neighbor)
                    while start < len(cells) and keys[start]==neighbor:
                        j=cells[start][3]
                        if i != j and sum((a-b)**2 for a,b in zip(p,points[j])) < h*h:
                            pairs.add((i,j))
                        start+=1
    return pairs


def pbf_iteration(points, h=.32, rest_density=1000., mass=6.):
    """Independent unbounded-neighbor PBF projection of small point clouds."""
    n=len(points)
    old_density=[]
    lambdas=[]
    for i, p in enumerate(points):
        density=mass*kernel_squared(0,h)
        grad_sum=[0.,0.,0.]
        sum_sq=0.
        for j, q in enumerate(points):
            if i==j:
                continue
            d=tuple(p[k]-q[k] for k in range(3))
            r2=dot(d,d)
            density+=mass*kernel_squared(r2,h)
            grad=gradient(d,h)
            grad=[g*mass/rest_density for g in grad]
            grad_sum=[grad_sum[k]+grad[k] for k in range(3)]
            sum_sq+=dot(grad,grad)
        sum_sq+=dot(grad_sum,grad_sum)
        c=max(density/rest_density-1,0)
        lambdas.append(-c/(sum_sq+1e-6))
        old_density.append(density)
    new=[]
    for i,p in enumerate(points):
        displacement=[0.,0.,0.]
        for j,q in enumerate(points):
            if i==j:
                continue
            d=tuple(p[k]-q[k] for k in range(3))
            r2=dot(d,d)
            ratio=kernel_squared(r2,h)/kernel_squared(.09*h*h,h)
            scorr=-.002*ratio**4
            grad=gradient(d,h)
            for k in range(3):
                displacement[k]+=(lambdas[i]+lambdas[j]+scorr)*grad[k]*mass/rest_density
        length=math.sqrt(dot(displacement,displacement))
        if length > .22*h:
            displacement=[v*(.22*h)/length for v in displacement]
        new.append(tuple(p[k]+displacement[k] for k in range(3)))
    return new, old_density, lambdas


class PBF3DReference(unittest.TestCase):
    def test_kernel_integrates_to_one(self):
        h=.36
        n=10000
        dr=h/n
        integral=0.
        for i in range(n+1):
            r=i*dr
            w=1 if i in (0,n) else 4 if i%2 else 2
            integral+=w*4*math.pi*r*r*kernel_squared(r*r,h)
        self.assertAlmostEqual(integral*dr/3,1.,delta=1e-11)

    def test_analytic_gradient_against_finite_difference(self):
        rng=random.Random(20261119)
        h=.48
        for _ in range(1500):
            p=tuple(rng.uniform(-.22,.22) for _ in range(3))
            if dot(p,p) >= .9*h*h:
                continue
            grad=gradient(p,h)
            eps=1e-6
            for k in range(3):
                a=list(p)
                b=list(p)
                a[k]+=eps
                b[k]-=eps
                numeric=(kernel_squared(dot(a,a),h)-kernel_squared(dot(b,b),h))/(2*eps)
                self.assertAlmostEqual(grad[k],numeric,delta=2e-7)

    def test_grid_neighborhood_matches_brute_force(self):
        rng=random.Random(7157)
        for repeat in range(120):
            count=rng.randrange(25,150)
            h=rng.uniform(.18,.9)
            points=[tuple(rng.uniform(-4,4) for _ in range(3)) for _ in range(count)]
            # Degeneracies: several particles in the same cell.
            points.extend(points[:3])
            self.assertEqual(pairs_grid(points,h),pairs_bruteforce(points,h))

    def test_pbf_reduces_compressed_fluid_density(self):
        cloud=[(x*.105,y*.105,z*.105) for y in range(3)
               for z in range(3) for x in range(3)]
        initial=max(pbf_iteration(cloud)[1])
        for _ in range(8):
            cloud, densities, lambdas=pbf_iteration(cloud)
            self.assertTrue(all(math.isfinite(v) and v<=0 for v in lambdas))
            self.assertTrue(all(all(math.isfinite(x) for x in p) for p in cloud))
        final=max(pbf_iteration(cloud)[1])
        self.assertLess(final,initial)

    def test_gradient_and_pressure_keep_center_of_mass_in_free_space(self):
        cloud=[(x*.12,y*.12,z*.12) for y in range(3)
               for z in range(3) for x in range(3)]
        before=tuple(sum(p[k] for p in cloud)/len(cloud) for k in range(3))
        next_cloud,_,_=pbf_iteration(cloud)
        after=tuple(sum(p[k] for p in next_cloud)/len(next_cloud) for k in range(3))
        for a,b in zip(before,after):
            self.assertAlmostEqual(a,b,delta=1e-12)

    def test_kernel_invalid_and_compact_support(self):
        self.assertEqual(kernel_squared(.25,.5),0.)
        self.assertEqual(kernel_squared(9.,.5),0.)
        self.assertEqual(gradient((0.,0.,0.),.5),(0.,0.,0.))
        self.assertEqual(gradient((1.,0.,0.),.5),(0.,0.,0.))

    def test_cpp_scene_registration_and_numerical_hotpath(self):
        kernel=(ROOT/"servers/physics_pbf_3d.h").read_text()
        impl=(ROOT/"scene/3d/physics/pbf_particle_fluid_3d.cpp").read_text()
        header=(ROOT/"scene/3d/physics/pbf_particle_fluid_3d.h").read_text()
        scene=(ROOT/"scene/register_scene_types.cpp").read_text()
        self.assertIn("GDCLASS(PBFParticleFluid3D, Node3D)",header)
        self.assertIn("GDREGISTER_CLASS(PBFParticleFluid3D);",scene)
        self.assertIn('pbf_particle_fluid_3d.h"',scene)
        self.assertIn("MAX_PARTICLES = 2048",header)
        self.assertIn("MAX_NEIGHBORS = 128",header)
        self.assertIn("PhysicsPBFKernel3D::gradient",impl)
        self.assertIn("physics_pbf_find_cell_begin_3d(",impl)
        self.assertIn("cells.sort();",impl)
        self.assertIn("const double constraint = MAX(density / double(rest_density) - 1.0, 0.0);",impl)
        self.assertIn("_apply_density_corrections();",impl)
        self.assertIn("_apply_xsph_viscosity();",impl)
        self.assertIn("void PBFParticleFluid3D::_resolve_world_collisions(",impl)
        self.assertIn("MAX_NEIGHBORS",impl)
        self.assertIn("pbf_particle_fluid_3d.cpp",str(ROOT/"scene/3d/physics/pbf_particle_fluid_3d.cpp"))
        self.assertNotIn("new Vector3",impl)
        self.assertIn("static _FORCE_INLINE_ real_t poly6(",kernel)
        self.assertIn("static _FORCE_INLINE_ Vector3 gradient(",kernel)

    def test_native_demo_and_ci_registration(self):
        native=(ROOT/"tests/servers/test_physics_pbf_3d.cpp").read_text()
        runtime=(ROOT/"tests/stress/physics_pbf_particle_fluid_3d_regression.gd").read_text()
        demo=(ROOT/"demo/physics_lab/pbf_water_3d.gd").read_text()
        lab=(ROOT/"demo/physics_lab/lab_3d.gd").read_text()
        ci=(ROOT/".github/workflows/whole-engine-stress.yml").read_text()
        self.assertIn("TEST_FORCE_LINK(test_physics_pbf_3d)",native)
        self.assertEqual(native.count('TEST_CASE("[PhysicsPBF3D]'),9)
        self.assertIn("PBFParticleFluid3D.new()",runtime)
        self.assertIn("fluid.simulation_enabled = true",runtime)
        self.assertIn("MultiMeshInstance3D.new()",demo)
        self.assertIn("PBF_WATER_3D.new()",lab)
        self.assertIn("add_velocity_pulse(",demo)
        self.assertIn('ClassDB::bind_method(D_METHOD("add_velocity_pulse"',impl)
        smoke = (ROOT / "demo/physics_lab/smoke_test.gd").read_text()
        self.assertIn("PBFWaterDemo/PBFWaterCPU",smoke)
        stress = (ROOT / "tests/stress/physics_pbf_particle_fluid_stress.gd").read_text()
        self.assertIn("Performance.TIME_PHYSICS_PROCESS",stress)
        runner = (ROOT / "tests/stress/run.py").read_text()
        self.assertIn('"physics_pbf_3d_enabled"',runner)
        self.assertIn('"physics_pbf_3d_disabled"',runner)
        self.assertIn("*[PhysicsPBF3D]*",ci)
        self.assertIn("physics_pbf_particle_fluid_3d_regression.gd",ci)


if __name__ == "__main__":
    unittest.main()
