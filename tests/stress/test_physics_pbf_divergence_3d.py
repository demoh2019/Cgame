"""Independent DFSPH-inspired velocity divergence projection reference.

A pressure-free PBF density position solver is already present in Cgame.
This patch performs unilateral SPH velocity correction AFTER that solver,
not both density/velocity Poisson solves of production DFSPH.
The reference deliberately uses an O(n^2) brute-force neighbor list;
C++ production code uses the existing sorted cell grid.
"""
import math
import random
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def dot(a, b):
    return sum(x*y for x, y in zip(a, b))


def add(a, b):
    return tuple(x+y for x, y in zip(a, b))


def sub(a, b):
    return tuple(x-y for x, y in zip(a, b))


def scale(a, scalar):
    return tuple(x*scalar for x in a)


def norm(a):
    return math.sqrt(dot(a, a))


def kernel_gradient(offset, h):
    r2 = dot(offset, offset)
    if not 0 < r2 < h*h:
        return (0., 0., 0.)
    return scale(offset, -945./(32.*math.pi*h**5)*(1.-r2/(h*h))**2)


def density_rates(positions, velocities, h=.42, mass=6.):
    rates = []
    for i, pi in enumerate(positions):
        rate = 0.
        for j, pj in enumerate(positions):
            if j == i:
                continue
            g = kernel_gradient(sub(pi, pj), h)
            rate += mass*dot(sub(velocities[i], velocities[j]), g)
        rates.append(rate)
    return rates


def project(positions, velocities, h=.42, mass=6., rest_density=1000.,
            iterations=8, relaxation=.9, cap=.12, tolerance=0.):
    velocities = list(velocities)
    snapshots = []
    n = len(positions)
    # Reference independent of native neighbor grid; cache gradients to
    # avoid O(iters*n*n) Python math overhead, not to change its physics.
    grad = [[kernel_gradient(sub(positions[i], positions[j]),h)
             if i != j else (0.,0.,0.)
             for j in range(n)] for i in range(n)]
    weighted = [[scale(g,mass/rest_density) for g in row] for row in grad]
    denominators = []
    for row in weighted:
        self_grad = tuple(sum(g[k] for g in row) for k in range(3))
        denominators.append(sum(dot(g,g) for g in row)+dot(self_grad,self_grad)+1e-6)
    def residual(v):
        return [max(sum(mass*dot(sub(v[i],v[j]),grad[i][j])
                        for j in range(n))/rest_density,0.)
                for i in range(n)]
    for _ in range(iterations):
        c = residual(velocities)
        snapshots.append(sum(c)/n)
        if snapshots[-1] <= tolerance:
            break
        lambdas = [-x/denominators[i] for i,x in enumerate(c)]
        changes = []
        for i in range(n):
            shift = tuple(sum((lambdas[i]+lambdas[j])*weighted[i][j][k]
                              for j in range(n)) * relaxation for k in range(3))
            length = norm(shift)
            if length > cap:
                shift = scale(shift,cap/length)
            changes.append(shift)
        velocities = [add(v, dv) for v,dv in zip(velocities,changes)]
    final = sum(residual(velocities))/n
    return velocities, snapshots+[final]


class PBFDivergenceReference(unittest.TestCase):
    def test_5000_random_pair_approach_and_separation_signs(self):
        rng = random.Random(20261119)
        for _ in range(5000):
            radius = rng.uniform(.04,.40)
            h = .42
            g = kernel_gradient((-radius,0.,0.),h)
            approach = rng.uniform(.001,8.)
            left=(approach,0.,0.)
            right=(-approach,0.,0.)
            rate=6.*dot(sub(left,right),g)
            self.assertGreater(rate,0.)
            self.assertLess(6.*dot(sub(right,left),g),0.)

    def test_static_and_uniform_velocity_have_zero_density_rate(self):
        positions = [(x*.19,y*.19,z*.19)
                     for x in range(-2,3) for y in range(-2,3) for z in range(-2,3)]
        zero = [(0.,0.,0.)]*len(positions)
        uniform = [(2.,-3.,1.)]*len(positions)
        self.assertTrue(all(abs(t) < 1e-14 for t in density_rates(positions,zero)))
        self.assertTrue(all(abs(t) < 1e-14 for t in density_rates(positions,uniform)))

    def test_compressed_cloud_is_significantly_relaxed(self):
        positions=[(x*.19,y*.19,z*.19)
                   for x in range(-2,3) for y in range(-2,3) for z in range(-2,3)]
        inward=[scale(p,-2.) for p in positions]
        before=sum(max(v,0.) for v in density_rates(positions,inward))/(1000.*len(positions))
        after_v, history=project(positions,inward,iterations=8,relaxation=.9,cap=.12)
        after=sum(max(v,0.) for v in density_rates(positions,after_v))/(1000.*len(positions))
        self.assertGreater(before,3.0)
        self.assertLess(after,before*0.10)
        self.assertEqual(len(history),9)
        self.assertTrue(all(a >= b-1e-12 for a,b in zip(history,history[1:])))
        self.assertTrue(all(math.isfinite(x) for v in after_v for x in v))

    def test_restoring_pairwise_linear_momentum_when_no_cap_saturates(self):
        positions=[(x*.19,y*.19,z*.19)
                   for x in range(-1,2) for y in range(-1,2) for z in range(-1,2)]
        v=[scale(p,-.4) for p in positions]
        result,_ = project(positions,v,iterations=3,relaxation=.8,cap=100.)
        before=tuple(sum(vv[k] for vv in v) for k in range(3))
        after=tuple(sum(vv[k] for vv in result) for k in range(3))
        self.assertTrue(all(abs(a-b)<1e-12 for a,b in zip(before,after)))

    def test_one_sided_constraint_never_forces_expansion(self):
        positions=[(-.1,0.,0.),(.1,0.,0.)]
        separating=[(-1.,0.,0.),(1.,0.,0.)]
        after,history=project(positions,separating,iterations=10)
        self.assertEqual(after,separating)
        self.assertEqual(history,[0.,0.])

    def test_large_velocity_corrections_are_capped(self):
        positions=[(-.18,0.,0.),(.18,0.,0.)]
        approaching=[(500.,0.,0.),(-500.,0.,0.)]
        next_v,_=project(positions,approaching,iterations=1,cap=.12)
        for before,after in zip(approaching,next_v):
            self.assertLessEqual(norm(sub(after,before)),.120001)

    def test_enabled_solver_is_deterministic_across_replays(self):
        rng=random.Random(56)
        points=[(x*.18,y*.18,z*.18) for x in range(4)
                for y in range(3) for z in range(3)]
        v=[(rng.uniform(-5,5),rng.uniform(-5,5),rng.uniform(-5,5))
           for _ in points]
        a,_=project(points,v,iterations=8,cap=.12)
        b,_=project(points,v,iterations=8,cap=.12)
        self.assertEqual(a,b)

    def test_native_source_contracts_and_bounded_disable(self):
        helper=(ROOT/"servers/physics_pbf_divergence_3d.h").read_text()
        cpp=(ROOT/"scene/3d/physics/pbf_particle_fluid_3d.cpp").read_text()
        h=(ROOT/"scene/3d/physics/pbf_particle_fluid_3d.h").read_text()
        self.assertIn("divergence_iterations = 0;",h)
        self.assertIn("divergence_velocity_changes.resize(p_count);",cpp)
        self.assertIn("divergence_multipliers.resize(p_count);",cpp)
        self.assertIn("if (divergence_iterations <= 0",cpp)
        self.assertIn("_update_grid();",cpp)
        self.assertIn("PhysicsPBFDivergence3D::density_rate_pair(",cpp)
        self.assertIn("PhysicsPBFDivergence3D::lagrange_multiplier(",cpp)
        self.assertIn("PhysicsPBFDivergence3D::pair_velocity_correction(",cpp)
        self.assertIn("PhysicsPBFDivergence3D::bounded_correction(",cpp)
        self.assertIn("average_positive_density_rate = _measure_positive_density_rate();",cpp)
        self.assertIn("_project_velocity_divergence();",cpp)
        self.assertIn("last_divergence_neighbor_evaluations",cpp)
        self.assertIn("return Math::is_finite(rate) ?",helper)

    def test_runtime_benchmark_and_ci_registration(self):
        native=(ROOT/"tests/servers/test_physics_pbf_divergence_3d.cpp").read_text()
        scene=(ROOT/"tests/stress/physics_pbf_divergence_3d_regression.gd").read_text()
        workflow=(ROOT/".github/workflows/physics-pbf-divergence.yml").read_text()
        stress=(ROOT/"tests/stress/stress.gd").read_text()
        lab=(ROOT/"demo/physics_lab/pbf_water_3d.gd").read_text()
        docs=(ROOT/"doc/classes/PBFParticleFluid3D.xml").read_text()
        self.assertEqual(native.count('TEST_CASE("[PhysicsPBFDivergence]'),8)
        self.assertIn("TEST_FORCE_LINK(test_physics_pbf_divergence_3d)",native)
        self.assertIn("divergence_iterations",scene)
        self.assertIn("test_physics_pbf_divergence_compiler.cpp",workflow)
        self.assertIn('"physics_pbf_divergence_3d_enabled"',stress)
        self.assertIn('"physics_pbf_divergence_3d_disabled"',stress)
        self.assertIn("KEY_G:",lab)
        self.assertIn('name="divergence_iterations"',docs)


if __name__ == "__main__":
    unittest.main()
