"""Independent brute-force predictive SPH density-pressure reference.

The native Cgame implementation is an opt-in pressure predictor added
before PBF advection, not a full DFSPH two-Poisson solver. This test
implements the same mathematical constraint with all-pairs neighbors,
not the native sorted-cell search, to catch neighbor/gradient errors.
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


def scale(a, k):
    return tuple(x*k for x in a)


def norm(a):
    return math.sqrt(dot(a, a))


def poly6(r2, h):
    return (315.0/(64*math.pi*h**3) * (1-r2/h**2)**3) if 0 <= r2 < h*h else 0.0


def grad_poly6(r, h):
    r2 = dot(r, r)
    if r2 <= 0 or r2 >= h*h:
        return (0., 0., 0.)
    return scale(r, -945.0/(32.0*math.pi*h**5)*(1-r2/h**2)**2)


def cloud(size=5, spacing=.175):
    half=(size-1)*.5
    return [(spacing*(x-half),spacing*(y-half),spacing*(z-half))
            for x in range(size) for y in range(size) for z in range(size)]


def pressure_projection(points, velocities, h=.42, mass=6., rest=1000.,
                        dt=1/60, iterations=8, relaxation=.8, cap=.15,
                        tolerance=0.):
    n=len(points)
    assert n==len(velocities) and n>0
    # All-pairs reference; cache raw pair gradients so the pressure
    # iterations can change only trial velocities, not particle geometry.
    gradient=[[grad_poly6(sub(points[i],points[j]),h) if i != j
               else (0.,0.,0.) for j in range(n)] for i in range(n)]
    density=[mass*sum(poly6(dot(sub(p,q),sub(p,q)),h) for q in points)
             for p in points]
    volume=mass/rest
    denominator=[]
    for row in gradient:
        g=[scale(v,volume) for v in row]
        gs=tuple(sum(gg[k] for gg in g) for k in range(3))
        denominator.append(sum(dot(gg,gg) for gg in g)+dot(gs,gs)+1e-6)

    velocity=list(velocities)
    history=[]
    for i in range(iterations+1):
        errors=[]
        for k in range(n):
            density_rate=mass*sum(dot(sub(velocity[k],velocity[j]),gradient[k][j])
                                  for j in range(n))
            predicted=density[k]+dt*density_rate
            errors.append(max(predicted/rest-1.,0.))
        history.append(sum(errors)/n)
        if i==iterations or history[-1] <= tolerance:
            break
        multipliers=[max(-error/dt / denominator[j],-1e6)
                     for j,error in enumerate(errors)]
        changes=[]
        for k in range(n):
            direction=tuple(sum((multipliers[k]+multipliers[j])*gradient[k][j][axis]
                                for j in range(n))*volume*relaxation for axis in range(3))
            length=norm(direction)
            if length > cap:
                direction=scale(direction,cap/length)
            changes.append(direction)
        velocity=[add(v,dv) for v,dv in zip(velocity,changes)]
    return velocity,history,density


class PBFPredictiveDensityReference(unittest.TestCase):
    def test_prediction_accounts_for_timestep_and_density_excess(self):
        rho=1020.
        rho_dot=150.
        dt=.02
        self.assertAlmostEqual(rho+dt*rho_dot,1023.)
        self.assertAlmostEqual(max((rho+dt*rho_dot)/1000.-1.,0.),.023)
        self.assertAlmostEqual(.023/dt,1.15)
        self.assertEqual(max((950.+dt*0)/1000-1,0),0.)

    def test_static_compressed_cloud_pressure_reduces_prediction(self):
        positions=cloud(5,.175)
        initial=[(0.,0.,0.)]*len(positions)
        after,history,density=pressure_projection(positions,initial)
        self.assertEqual(len(history),9)
        self.assertGreater(history[0],.02)
        self.assertLess(history[-1],history[0]*.01)
        self.assertTrue(all(a>=b-1e-10 for a,b in zip(history,history[1:])))
        self.assertTrue(all(math.isfinite(v) for vv in after for v in vv))
        self.assertGreater(max(density),1000.)

    def test_inward_advection_is_corrected_before_position_update(self):
        points=cloud(5,.175)
        v=[scale(p,-1.5) for p in points]
        after,history,_=pressure_projection(points,v)
        self.assertGreater(history[0],.035)
        self.assertLess(history[-1],history[0]*.2)
        self.assertTrue(all(norm(sub(a,b))<=8*.15+1e-9
                            for a,b in zip(after,v)))

    def test_symmetric_uncapped_solver_preserves_total_linear_momentum(self):
        points=cloud(3,.16)
        v=[scale(p,-.5) for p in points]
        after,history,_=pressure_projection(points,v,mass=15.,
                                             cap=100.,iterations=6)
        before=tuple(sum(p[k] for p in v) for k in range(3))
        final=tuple(sum(p[k] for p in after) for k in range(3))
        self.assertTrue(all(abs(a-b)<1e-11 for a,b in zip(before,final)))
        self.assertTrue(math.isfinite(history[-1]))

    def test_under_dense_sediment_does_not_generate_negative_pressure(self):
        points=[(-.18,0.,0.),(.18,0.,0.)]
        velocities=[(-1.,0.,0.),(1.,0.,0.)]
        after,history,density=pressure_projection(points,velocities)
        self.assertEqual(after,velocities)
        self.assertTrue(all(v==0 for v in history))
        self.assertTrue(all(d<1000. for d in density))

    def test_individual_velocity_changes_do_not_exceed_cap(self):
        points=cloud(3,.12)
        v=[scale(p,-10.) for p in points]
        after,history,_=pressure_projection(points,v,mass=25.,
                                             iterations=1,cap=.025)
        self.assertEqual(len(history),2)
        for old,new in zip(v,after):
            self.assertLessEqual(norm(sub(old,new)),.0250001)

    def test_3000_random_density_rate_signs_and_finiteness(self):
        rng=random.Random(20261119)
        for _ in range(3000):
            h=.42
            d=rng.uniform(.01,.41)
            g=grad_poly6((-d,0.,0.),h)
            incoming=rng.uniform(.001,8)
            rate=6.*dot((2*incoming,0,0),g)
            self.assertGreater(rate,0.)
            error=max((1000.+(1./60.)*rate)/1000.-1.,0.)
            self.assertGreater(error,0.)
            self.assertTrue(math.isfinite(error))
            self.assertEqual(max((1000.-(1./60.)*rate)/1000.-1.,0.),0.)

    def test_repeated_projector_is_deterministic(self):
        points=cloud(4,.18)
        rng=random.Random(771)
        v=[tuple(rng.uniform(-2,2) for _ in range(3)) for _ in points]
        a=pressure_projection(points,v)
        b=pressure_projection(points,v)
        self.assertEqual(a,b)

    def test_compiler_and_native_integration_are_registered(self):
        header=(ROOT/"servers/physics_pbf_density_pressure_3d.h").read_text()
        h=(ROOT/"scene/3d/physics/pbf_particle_fluid_3d.h").read_text()
        src=(ROOT/"scene/3d/physics/pbf_particle_fluid_3d.cpp").read_text()
        native=(ROOT/"tests/servers/test_physics_pbf_density_pressure_3d.cpp").read_text()
        stress=(ROOT/"tests/stress/physics_pbf_particle_fluid_stress.gd").read_text()
        workflow=(ROOT/".github/workflows/physics-pbf-density-pressure.yml").read_text()
        self.assertIn("density_pressure_iterations = 0",h)
        self.assertIn("PhysicsPBFDensityPressure3D::positive_density_error",src)
        self.assertIn("PhysicsPBFDensityPressure3D::predicted_density",src)
        self.assertIn("density_pressure_velocities.resize(p_count)",src)
        self.assertIn("density_pressure_corrections.resize(p_count)",src)
        self.assertIn("_project_predictive_density_pressure(p_delta);",src)
        self.assertIn("const Vector3 *pressure_velocity",src)
        self.assertIn("if (density_pressure_iterations <= 0",src)
        self.assertIn("density_pressure_neighbor_evaluations",src)
        self.assertIn("pressure_rate_constraint",header)
        self.assertEqual(native.count('TEST_CASE("[PhysicsPBFDensityPressure]'),8)
        self.assertIn("TEST_FORCE_LINK(test_physics_pbf_density_pressure_3d)",native)
        self.assertIn("with_density_pressure",stress)
        self.assertIn("test_physics_pbf_density_pressure_compiler.cpp",workflow)
        self.assertIn("physics_pbf_density_pressure_3d_regression.gd",workflow)

    def test_demo_and_docs_reveal_pressure_controls(self):
        lab=(ROOT/"demo/physics_lab/pbf_water_3d.gd").read_text()
        docs=(ROOT/"doc/classes/PBFParticleFluid3D.xml").read_text()
        runner=(ROOT/"tests/stress/stress.gd").read_text()
        self.assertIn("KEY_H:",lab)
        self.assertIn('name="density_pressure_iterations"',docs)
        self.assertIn('"physics_pbf_density_pressure_3d_enabled"',runner)
        self.assertIn('"physics_pbf_density_pressure_3d_disabled"',runner)


if __name__=="__main__":
    unittest.main()
