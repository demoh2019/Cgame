"""Linearized conservative CCD for nonadjacent self-edge pairs in Cgame Jolt.

Checks reference geometry and source invariants; native C++ compilation and
scene behavior are tested separately by whole-engine-stress.yml.
"""
import math
import random
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "modules/jolt_physics/spaces/jolt_space_3d.cpp"
SETTINGS = ROOT / "modules/jolt_physics/jolt_project_settings.cpp"
HEADER = ROOT / "modules/jolt_physics/jolt_project_settings.h"
NATIVE = ROOT / "tests/stress/jolt_soft_self_edge_sweep/swept_self_edges_regression.gd"
PROJECT = ROOT / "tests/stress/jolt_soft_self_edge_sweep/project.godot"


def sub(a, b):
    return tuple(x-y for x, y in zip(a, b))


def addscaled(a, v, t):
    return tuple(x+t*y for x, y in zip(a, v))


def dot(a, b):
    return sum(x*y for x, y in zip(a, b))


def magnitude(v):
    return math.sqrt(dot(v, v))


def closest(p0, p1, q0, q1):
    """Independent closest points on two clamped segments."""
    da, db, r = sub(p1, p0), sub(q1, q0), sub(p0, q0)
    aa, ee = dot(da, da), dot(db, db)
    if not math.isfinite(aa) or not math.isfinite(ee) or min(aa, ee) <= 1e-12:
        return None
    b, c, f = dot(da, db), dot(da, r), dot(db, r)
    denominator = aa*ee - b*b
    if not all(math.isfinite(v) for v in (denominator, c, f)):
        return None
    s = max(0., min(1., (b*f-c*ee)/denominator)) if denominator > 1e-12 else 0.
    t = (b*s + f) / ee
    if t < 0:
        t, s = 0., max(0., min(1., -c/aa))
    elif t > 1:
        t, s = 1., max(0., min(1., (b-c)/aa))
    return s, t, addscaled(p0, da, s), addscaled(q0, db, t)


def bounds(p0, p1):
    return (tuple(min(a, b) for a, b in zip(p0, p1)),
            tuple(max(a, b) for a, b in zip(p0, p1)))


def overlaps(a, b, radius):
    pmin, pmax = a
    qmin, qmax = b
    return all(pmax[k]+radius >= qmin[k] and qmax[k]+radius >= pmin[k] for k in range(3))


def predict(p0, p1, q0, q1, vp0, vp1, vq0, vq1,
            dt=1/60, radius=.14, max_sweep=1.0, budget=512):
    """Reference of the same 16-step bounded conservative advancement."""
    if dt <= 0 or radius <= 0 or max_sweep <= 0:
        return None
    speed_bound = max(magnitude(sub(a,b))
                      for a in (vp0, vp1) for b in (vq0, vq1))
    if not math.isfinite(speed_bound) or speed_bound <= 1e-6 or speed_bound*dt > max_sweep:
        return None
    time, used = 0., 0
    for _ in range(min(16, budget)):
        used += 1
        pose = tuple(addscaled(a,v,time) for a,v in zip(
            (p0,p1,q0,q1), (vp0,vp1,vq0,vq1)))
        result = closest(*pose)
        if result is None:
            return None
        s,t,a,b = result
        gap = sub(b,a)
        distance = magnitude(gap)
        if not math.isfinite(distance):
            return None
        if time > 0 and distance <= radius + 1e-4:
            va = tuple((1-s)*vp0[k]+s*vp1[k] for k in range(3))
            vb = tuple((1-t)*vq0[k]+t*vq1[k] for k in range(3))
            dv = sub(vb,va)
            if distance > 1e-6:
                normal = tuple(x/distance for x in gap)
            elif magnitude(dv)>1e-6:
                normal = tuple(-x/magnitude(dv) for x in dv)
            else:
                return None
            if dot(dv,normal)>=-1e-6:
                return None
            return time,s,t,normal,used
        if distance<=radius:
            return None
        advance=(distance-radius)/speed_bound
        if not math.isfinite(advance) or advance<=1e-8*dt or time+advance>dt:
            return None
        time+=advance
    return None


def x_edge(z, x=0):
    return (x-.9,2.,z),(x+.9,2.,z)


def y_edge(z=0, x=0):
    return (x,1.1,z),(x,2.9,z)


ZERO=(0.,0.,0.)


class SoftSelfEdgeSweepContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.src=SRC.read_text(encoding="utf-8")
        cls.settings=SETTINGS.read_text(encoding="utf-8")
        cls.header=HEADER.read_text(encoding="utf-8")
        cls.solver=cls.src.split("static void resolve_soft_body_self_edge_contacts(",1)[1].split(
            "static void clear_pending_index(",1)[0]
        cls.predictor=cls.src.split("static bool predict_soft_edge_edge_sweep(",1)[1].split(
            "static void resolve_soft_soft_edge_edge_contacts(",1)[0]
        cls.prestep=cls.src.split("void JoltSpace3D::_pre_step(float p_step) {",1)[1].split(
            "void JoltSpace3D::_post_step(float p_step) {",1)[0]

    def test_fast_self_edge_crossing_detected(self):
        p0,p1=x_edge(-.38)
        q0,q1=y_edge()
        result=predict(p0,p1,q0,q1,(0,0,35),(0,0,35),ZERO,ZERO)
        self.assertIsNotNone(result)
        time,s,t,normal,used=result
        self.assertAlmostEqual(time,(.38-.14)/35,places=6)
        self.assertAlmostEqual(s,.5,places=5)
        self.assertAlmostEqual(t,.5,places=5)
        self.assertGreater(normal[2],.99)
        self.assertGreater(magnitude(sub(p0,q0)),.14)
        self.assertLessEqual(used,16)

    def test_reversed_edge_order_and_static_target(self):
        p0,p1=x_edge(-.38)
        q0,q1=y_edge()
        a=predict(p0,p1,q0,q1,(0,0,35),(0,0,35),ZERO,ZERO)
        b=predict(q0,q1,p0,p1,ZERO,ZERO,(0,0,35),(0,0,35))
        self.assertIsNotNone(b)
        self.assertAlmostEqual(a[0],b[0])
        self.assertLess(dot(a[3],b[3]),-.99)

    def test_parallel_and_moving_edges(self):
        p0,p1=(-1,.4,0),(1,.4,0)
        q0,q1=(-1,0,0),(1,0,0)
        first=predict(p0,p1,q0,q1,(0,-30,0),(0,-30,0),ZERO,ZERO)
        second=predict(p0,p1,q0,q1,ZERO,ZERO,(0,30,0),(0,30,0))
        self.assertIsNotNone(first)
        self.assertIsNotNone(second)
        self.assertAlmostEqual(first[0],(.4-.14)/30,places=6)
        self.assertAlmostEqual(first[0],second[0],places=6)

    def test_disabled_travel_limit_and_outgoing(self):
        p0,p1=x_edge(-.38)
        q0,q1=y_edge()
        self.assertIsNone(predict(p0,p1,q0,q1,ZERO,ZERO,ZERO,ZERO))
        self.assertIsNone(predict(p0,p1,q0,q1,(0,0,-35),(0,0,-35),ZERO,ZERO))
        self.assertIsNone(predict(p0,p1,q0,q1,(0,0,70),(0,0,70),ZERO,ZERO,max_sweep=.5))
        self.assertIsNone(predict(p0,p1,q0,q1,(0,0,35),(0,0,35),ZERO,ZERO,budget=1))
        self.assertIsNone(predict(p0,p1,q0,q1,(0,0,35),(0,0,35),ZERO,ZERO,dt=0))

    def test_current_overlap_does_not_trigger_future_ccd(self):
        p0,p1=x_edge(-.04)
        q0,q1=y_edge()
        self.assertIsNone(predict(p0,p1,q0,q1,(0,0,35),(0,0,35),ZERO,ZERO))

    def test_swept_aabb_margin_is_conservative_when_predictor_accepts(self):
        rng=random.Random(21)
        for _ in range(400):
            distance=rng.uniform(.18,.8)
            speed=rng.uniform(18,100)
            p0,p1=x_edge(-distance)
            q0,q1=y_edge()
            result=predict(p0,p1,q0,q1,(0,0,speed),(0,0,speed),ZERO,ZERO)
            if result is not None:
                self.assertTrue(overlaps(bounds(p0,p1),bounds(q0,q1),.14+1))
                self.assertLessEqual(speed/60,1)
            if distance>.14+1:
                self.assertFalse(overlaps(bounds(p0,p1),bounds(q0,q1),.14+1))

    def test_randomized_crossings_match_analytic_toi(self):
        rng=random.Random(32)
        checked=0
        for _ in range(200):
            distance=rng.uniform(.16,.75)
            speed=rng.uniform(22,90)
            if (distance-.14)/speed>=1/60 or speed/60>1:
                continue
            p0,p1=x_edge(-distance)
            q0,q1=y_edge()
            result=predict(p0,p1,q0,q1,(0,0,speed),(0,0,speed),ZERO,ZERO)
            self.assertIsNotNone(result,(distance,speed))
            self.assertAlmostEqual(result[0],(distance-.14)/speed,delta=2e-5)
            checked+=1
        self.assertGreater(checked,45)

    def test_mass_weighted_impulses_balance_internal_momentum(self):
        weights=[.4,.6,.25,.75]
        inverses=[1,2,3,4]
        effective=sum(w*w*m for w,m in zip(weights,inverses))
        impulse=7/effective
        delta=[(-1 if i<2 else 1)*weights[i]*inverses[i]*impulse for i in range(4)]
        self.assertAlmostEqual(sum(delta[i]/inverses[i] for i in range(4)),0)
        self.assertIn("a0.mVelocity -= impulse * (wa0 * a0.mInvMass);",self.solver)
        self.assertIn("b1.mVelocity += impulse * (wb1 * b1.mInvMass);",self.solver)

    def test_default_disabled_and_bvh_expanded_both_paths(self):
        self.assertIn("soft_body_self_speculative_edge_ccd = false;",self.header)
        self.assertIn('simulation/soft_body_self_speculative_edge_ccd"), false',self.settings)
        self.assertIn("soft_body_self_speculative_edge_ccd = GLOBAL_GET(",self.settings)
        self.assertIn("const bool swept_self_edge_ccd = JoltProjectSettings::soft_body_self_speculative_edge_ccd",self.solver)
        self.assertIn("const float candidate_radius = radius +",self.solver)
        self.assertIn("query_soft_self_edge_bvh(p_min, p_max, candidate_radius,",self.solver)
        self.assertIn("!soft_self_edge_bounds_overlap(p_min, p_max, q_min, q_max, candidate_radius)",self.solver)
        self.assertIn("use_edge_bvh ? r_scratch.edge_bvh.candidates[candidate] : candidate",self.solver)

    def test_predictor_shared_work_budget_and_topology(self):
        self.assertIn("!predict_soft_edge_edge_sweep(p0, p1, q0, q1,",self.solver)
        self.assertIn("r_budget, s, t, swept_normal",self.solver)
        self.assertIn("iteration < MAX_SOFT_EDGE_SWEEP_ITERATIONS && r_budget > 0",self.predictor)
        self.assertIn("--r_budget;",self.predictor)
        self.assertIn("--r_budget; // Every tested candidate",self.solver)
        self.assertIn("if (soft_self_edges_are_neighbors(key_a, key_b, edges))",self.solver)
        self.assertIn("if (j <= i)",self.solver)
        self.assertIn("self_edge_budget = self_edges ? self_budget / 2 : 0;",self.prestep)

    def test_future_contact_has_no_penetration_bias_or_position_projection(self):
        self.assertIn("if (!swept_contact && r_scratch.position_projection_ready)",self.solver)
        self.assertIn("const float recovery_speed = swept_contact ? 0.0f :",self.solver)
        self.assertIn("swept_contact ? JoltProjectSettings::soft_body_soft_ccd_max_correction_speed",self.solver)
        self.assertIn("const float distance = swept_contact ? radius :",self.solver)
        self.assertIn("JPH::Vec3 normal = swept_normal;",self.solver)
        self.assertIn("const float correction = MIN(MAX(recovery_speed - normal_speed, 0.0f), max_correction);",self.solver)

    def test_native_fixture_isolated_self_cdd_and_control(self):
        project=PROJECT.read_text(encoding="utf-8")
        native=NATIVE.read_text(encoding="utf-8")
        self.assertIn("soft_body_self_speculative_edge_ccd=true",project)
        self.assertIn("soft_body_soft_contacts=false",project)
        self.assertIn("soft_body_self_position_projection=false",project)
        self.assertIn("soft_body_apply_point_impulse",native)
        self.assertIn("_triangle_pair_mesh(7.0, true)",native)
        self.assertIn("PASS: Jolt swept self edge-edge CCD versus unopposed control",native)


if __name__=="__main__":
    unittest.main()
