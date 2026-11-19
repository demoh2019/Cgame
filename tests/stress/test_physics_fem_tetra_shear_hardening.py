"""Independent contracts for hardening-aware Hencky tetrahedral plasticity.

No third-party dependencies. This tests the *material law* and source
wiring; complete engine builds and physically coupled scenes are separate.
"""
import math
from pathlib import Path
import random
import unittest

ROOT = Path(__file__).resolve().parents[2]


def relaxation(rate, dt, hardening):
    return (1-math.exp(-rate*dt*(1+hardening))) / (1+hardening)


def flow_equivalent(eq, history, yield_strain, hardening, factor, cap):
    if history >= cap or eq <= yield_strain + hardening*history:
        return eq, history
    increment = min(cap-history, factor*(eq-yield_strain-hardening*history))
    return eq-increment, history+increment


def dev_strain_principal(log_stretches):
    avg = sum(log_stretches)/3.
    dev = tuple(x-avg for x in log_stretches)
    eq = math.sqrt(2./3.*sum(x*x for x in dev))
    return dev,eq


def determinant(mat):
    return (mat[0][0]*(mat[1][1]*mat[2][2]-mat[1][2]*mat[2][1])
            -mat[0][1]*(mat[1][0]*mat[2][2]-mat[1][2]*mat[2][0])
            +mat[0][2]*(mat[1][0]*mat[2][1]-mat[1][1]*mat[2][0]))


def multiply(a,b):
    return [[sum(a[i][k]*b[k][j] for k in range(3))
             for j in range(3)] for i in range(3)]


class TetraHardeningReference(unittest.TestCase):
    def test_4000_random_isochoric_principal_flow(self):
        rng=random.Random(0xFADE11)
        for _ in range(4000):
            logs=tuple(math.log(rng.uniform(.5,2.2)) for j in range(3))
            dev,eq=dev_strain_principal(logs)
            history=rng.uniform(0.,.3)
            cap=rng.uniform(.4,4.)
            yield_strain=rng.uniform(0.,.2)
            H=rng.uniform(0.,4.)
            factor=relaxation(rng.uniform(.1,20.),rng.uniform(.001,.1),H)
            residual,after=flow_equivalent(eq,history,yield_strain,H,factor,cap)
            increment=after-history
            if eq>0.:
                updated=tuple(logs[i]-increment*dev[i]/eq for i in range(3))
            else:
                updated=logs
            _,measured=dev_strain_principal(updated)
            self.assertAlmostEqual(measured,residual,delta=1e-12)
            self.assertAlmostEqual(sum(updated),sum(logs),delta=1e-12)
            self.assertGreaterEqual(after,history-1e-12)
            self.assertLessEqual(after,cap+1e-12)

    def test_2000_hardening_reduces_further_yield(self):
        rng=random.Random(0xBADA55)
        for _ in range(2000):
            equivalent=rng.uniform(.2,1.5)
            history=rng.uniform(0.,.2)
            yield_strain=rng.uniform(0.,.12)
            rate=rng.uniform(.1,10.)
            dt=rng.uniform(.01,.3)
            none=flow_equivalent(equivalent,history,yield_strain,0.,relaxation(rate,dt,0.),3.)
            hardening=rng.uniform(.1,4.)
            hard=flow_equivalent(equivalent,history,yield_strain,hardening,
                                 relaxation(rate,dt,hardening),3.)
            self.assertLessEqual(hard[1],none[1]+1e-12)
            self.assertGreaterEqual(hard[0]+1e-12,none[0])

    def test_2000_hardening_substep_invariance(self):
        rng=random.Random(0xDECAFE)
        for _ in range(2000):
            logs=tuple(math.log(rng.uniform(.5,2.)) for _ in range(3))
            _,eq=dev_strain_principal(logs)
            history=0.
            yield_strain=rng.uniform(.0,.12)
            H=rng.uniform(.0,4.)
            rate=rng.uniform(.1,18.)
            dt=rng.uniform(.005,.5)
            full=flow_equivalent(eq,history,yield_strain,H,relaxation(rate,dt,H),3.)
            split=(eq,history)
            small=relaxation(rate,dt/20.,H)
            for _ in range(20):
                split=flow_equivalent(split[0],split[1],yield_strain,H,small,3.)
            self.assertAlmostEqual(full[0],split[0],delta=1e-11)
            self.assertAlmostEqual(full[1],split[1],delta=1e-11)

    def test_1000_skew_rest_and_material_rotation(self):
        rng=random.Random(0xD38AE)
        for _ in range(1000):
            # A realistic nonorthogonal undeformed tetrahedral basis.
            dm=[[rng.uniform(.8,1.5),rng.uniform(-.3,.3),rng.uniform(-.3,.3)],
                [0.,rng.uniform(.8,1.5),rng.uniform(-.3,.3)],
                [0.,0.,rng.uniform(.8,1.5)]]
            det=determinant(dm)
            self.assertGreater(det,0.)
            # Positive determinant and pure world rotation: no strain
            # despite the rest matrix being highly nonorthogonal.
            a=rng.uniform(-math.pi,math.pi)
            c,s=math.cos(a),math.sin(a)
            R=[[c,-s,0],[s,c,0],[0,0,1]]
            current=multiply(R,dm)
            self.assertAlmostEqual(determinant(current),det,delta=1e-12)
            self.assertAlmostEqual(determinant(R),1.,delta=1e-12)

    def test_setting_and_no_extra_memory(self):
        engine=(ROOT/"modules/godot_physics_3d/godot_soft_body_3d.cpp").read_text()
        space=(ROOT/"modules/godot_physics_3d/godot_space_3d.h").read_text()
        space_cpp=(ROOT/"modules/godot_physics_3d/godot_space_3d.cpp").read_text()
        server=(ROOT/"servers/physics_3d/physics_server_3d.cpp").read_text()
        header=(ROOT/"servers/physics_fem_tetra_deviatoric_plasticity.h").read_text()
        self.assertIn("soft_body_tetra_shear_plastic_hardening = 0.0;",space)
        self.assertIn("soft_body_tetra_shear_plastic_hardening = Math::is_finite(",space_cpp)
        self.assertIn('"physics/3d/solver/soft_body_tetra_shear_plastic_hardening"',server)
        self.assertIn("get_soft_body_tetra_shear_plastic_hardening()",engine)
        self.assertIn("tetra.plastic_deviatoric_strain, hardening)",engine)
        self.assertIn("p_hardening = 0.0",header)
        self.assertIn("p_hardening * r_accumulated_strain",header)
        self.assertIn("std::cbrt(determinant_ratio)",header)
        self.assertIn("r_accumulated_strain = updated_strain;",header)
        self.assertNotIn("xpbd_fem_shear_hardening_buffer",engine)


if __name__=="__main__":
    unittest.main()
