"""Cgame/Jolt conservative CCD of nonlocal points vs deforming self triangles.

These are independent mathematical/source contracts, NOT a native engine run.
Native test: tests/stress/jolt_soft_self_vf_sweep/swept_self_triangle_regression.gd
"""
import math
from pathlib import Path
import random
import unittest

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "modules/jolt_physics/spaces/jolt_space_3d.cpp"
SETTINGS = ROOT / "modules/jolt_physics/jolt_project_settings.cpp"
HEADER = ROOT / "modules/jolt_physics/jolt_project_settings.h"
PROJECT = ROOT / "tests/stress/jolt_soft_self_vf_sweep/project.godot"
NATIVE = ROOT / "tests/stress/jolt_soft_self_vf_sweep/swept_self_triangle_regression.gd"


def add(a, b):
    return tuple(x + y for x, y in zip(a, b))


def sub(a, b):
    return tuple(x - y for x, y in zip(a, b))


def mul(a, k):
    return tuple(x * k for x in a)


def dot(a, b):
    return sum(x*y for x, y in zip(a, b))


def cross(a, b):
    return (a[1]*b[2]-a[2]*b[1],
            a[2]*b[0]-a[0]*b[2],
            a[0]*b[1]-a[1]*b[0])


def norm(v):
    return math.sqrt(dot(v, v))


def closest_triangle(p, a, b, c):
    """Ericson seven-region nearest point, independent Python reference."""
    ab, ac = sub(b, a), sub(c, a)
    if dot(cross(ab, ac), cross(ab, ac)) <= 1e-14:
        return None
    ap = sub(p, a)
    d1, d2 = dot(ab, ap), dot(ac, ap)
    if d1 <= 0 and d2 <= 0:
        weights = (1., 0., 0.)
    else:
        bp = sub(p, b)
        d3, d4 = dot(ab, bp), dot(ac, bp)
        if d3 >= 0 and d4 <= d3:
            weights = (0., 1., 0.)
        else:
            vc = d1*d4 - d3*d2
            if vc <= 0 and d1 >= 0 and d3 <= 0:
                v = d1/(d1-d3)
                weights = (1-v, v, 0.)
            else:
                cp = sub(p, c)
                d5, d6 = dot(ab, cp), dot(ac, cp)
                if d6 >= 0 and d5 <= d6:
                    weights = (0., 0., 1.)
                else:
                    vb = d5*d2 - d1*d6
                    if vb <= 0 and d2 >= 0 and d6 <= 0:
                        w = d2/(d2-d6)
                        weights = (1-w, 0., w)
                    else:
                        va = d3*d6-d5*d4
                        if va <= 0 and d4-d3 >= 0 and d5-d6 >= 0:
                            w = (d4-d3)/((d4-d3)+(d5-d6))
                            weights = (0., 1-w, w)
                        else:
                            total = va+vb+vc
                            if not math.isfinite(total) or total <= 0:
                                return None
                            v, w = vb/total, vc/total
                            weights = (1-v-w, v, w)
    near = tuple(sum(weights[i]*tri[k] for i, tri in enumerate((a,b,c)))
                 for k in range(3))
    return near, weights


ZERO = (0., 0., 0.)
FACE = ((-1., 0., -1.), (1., 0., -1.), (0., 0., 1.))


def predict(point, point_vel, face=FACE, face_vel=(ZERO, ZERO, ZERO),
            dt=1/60, radius=.12, max_sweep=1, budget=512):
    """One-step bounded conservative advancement of an independently moving triangle.

    Every call's work (including failed distance checks) consumes one unit.
    """
    if not all(math.isfinite(x) for x in (dt, radius, max_sweep)):
        return None
    if dt <= 0 or radius <= 0 or max_sweep <= 0:
        return None
    speed_sq = max(dot(sub(point_vel, v), sub(point_vel, v)) for v in face_vel)
    if not math.isfinite(speed_sq) or speed_sq <= 1e-12:
        return None
    speed = math.sqrt(speed_sq)
    if not math.isfinite(speed*dt) or speed*dt > max_sweep:
        return None
    elapsed = 0.
    for iteration in range(min(16, budget)):
        p = add(point, mul(point_vel, elapsed))
        triangle = tuple(add(a, mul(v, elapsed)) for a, v in zip(face, face_vel))
        nearest = closest_triangle(p, *triangle)
        if nearest is None:
            return None
        closest, weights = nearest
        gap = sub(p, closest)
        dist = norm(gap)
        if not math.isfinite(dist):
            return None
        if elapsed > 0 and dist <= radius + 1e-4:
            fv = tuple(sum(weights[i]*face_vel[i][k] for i in range(3))
                       for k in range(3))
            relative = sub(point_vel, fv)
            if dist > 1e-6:
                normal = mul(gap, 1./dist)
            elif norm(relative)>1e-6:
                normal = mul(relative, -1./norm(relative))
            else:
                return None
            if dot(relative, normal) >= -1e-6:
                return None
            return elapsed, weights, normal, iteration+1
        if dist <= radius:
            return None
        advance = (dist-radius)/speed
        if not math.isfinite(advance) or advance <= 1e-8*dt or elapsed+advance>dt:
            return None
        elapsed += advance
    return None


def point_over_aabb(point, face, radius):
    minimum = [min(v[k] for v in face) for k in range(3)]
    maximum = [max(v[k] for v in face) for k in range(3)]
    return all(minimum[k]-radius<=point[k]<=maximum[k]+radius for k in range(3))


class SoftSelfVFSweepContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.src = SOURCE.read_text(encoding="utf-8")
        cls.settings = SETTINGS.read_text(encoding="utf-8")
        cls.header = HEADER.read_text(encoding="utf-8")
        cls.predictor = cls.src.split("static bool predict_soft_self_vertex_face_sweep(",1)[1].split(
            "static void resolve_soft_body_self_contacts(",1)[0]
        cls.solver = cls.src.split("static void resolve_soft_body_self_contacts(",1)[1].split(
            "static bool soft_self_edges_are_neighbors(",1)[0]
        cls.prestep = cls.src.split("void JoltSpace3D::_pre_step(float p_step) {",1)[1].split(
            "void JoltSpace3D::_post_step(float p_step) {",1)[0]

    def test_fast_vertex_crosses_face_in_single_step(self):
        result = predict((0.,.38,0.), (0.,-35.,0.))
        self.assertIsNotNone(result)
        time, weights, normal, iterations = result
        self.assertAlmostEqual(time, (.38-.12)/35, places=7)
        self.assertGreater(normal[1], .99)
        self.assertAlmostEqual(sum(weights), 1., places=10)
        self.assertTrue(all(x>=0 for x in weights))
        self.assertLessEqual(iterations, 16)

    def test_both_sides_and_both_triangle_windings(self):
        for face in (FACE, tuple(reversed(FACE))):
            for side in (-1,1):
                result = predict((0.,side*.50,0.), (0.,-side*40,0.), face)
                self.assertIsNotNone(result, (face,side))
                self.assertGreater(normal_y := result[2][1]*side, .99)
                self.assertAlmostEqual(result[0], (.50-.12)/40, places=7)

    def test_translating_deformable_face_uses_relative_velocity(self):
        moving_up = ((0.,36.,0.),)*3
        result = predict((0.,.5,0.), ZERO, face_vel=moving_up)
        self.assertIsNotNone(result)
        self.assertAlmostEqual(result[0], (.5-.12)/36, places=7)
        self.assertIsNone(predict((0.,.5,0.), (0.,36.,0.), face_vel=moving_up))

    def test_shearing_triangle_does_not_drop_linear_face_contact(self):
        shear = ((-10.,0.,0.), (10.,0.,0.), (0.,0.,0.))
        result = predict((0.,.42,0.), (0.,-35.,0.), face_vel=shear)
        self.assertIsNotNone(result)
        self.assertLess(result[0], 1/60)
        self.assertAlmostEqual(sum(result[1]),1.,places=8)

    def test_fast_rotation_bound_catches_high_velocity_corner(self):
        fast_corners = ((300.,0.,0.), (-300.,0.,0.), ZERO)
        # A mean-vertex speed of zero would be unsafe: actual rotating
        # face corners travel far beyond the permitted sweep horizon.
        self.assertIsNone(predict((0.,.4,0.), (0.,-35.,0.), face_vel=fast_corners))

    def test_edge_or_corner_nearest_feature_can_be_contact(self):
        face = ((-1.,0.,-1.),(1.,0.,-1.),(0.,0.,1.))
        result = predict((2.,.06,-1.), (-100.,0.,0.), face,
                         dt=1/60, radius=.12, max_sweep=2)
        self.assertIsNotNone(result)
        self.assertLess(result[0], 1/60)
        self.assertAlmostEqual(result[1][1], 1., delta=.08)

    def test_outgoing_stationary_initial_overlap_and_grazing(self):
        self.assertIsNone(predict((0.,.38,0.), ZERO))
        self.assertIsNone(predict((0.,.38,0.), (0.,35.,0.)))
        self.assertIsNone(predict((0.,.04,0.), (0.,-35.,0.)))
        self.assertIsNone(predict((0.,.38,0.), (35.,0.,0.)))
        self.assertIsNone(predict((0.,.38,0.), (0.,-35.,0.), budget=1))

    def test_budget_travel_horizon_and_degenerate_geometry(self):
        self.assertIsNone(predict((0.,.38,0.), (0.,-35.,0.), max_sweep=.4))
        self.assertIsNone(predict((0.,.38,0.), (0.,-35.,0.),dt=.004))
        self.assertIsNone(predict((0.,.38,0.), (0.,-35.,0.),dt=0))
        self.assertIsNone(predict((0.,.38,0.), (0.,-35.,0.),
                                  face=((0.,0.,0.),)*3))
        self.assertIsNone(predict((0.,.38,0.), (0.,-35.,0.), budget=0))

    def test_randomized_linear_sweeps_match_analytic_time_of_impact(self):
        rng = random.Random(20261119)
        successes = 0
        for _ in range(650):
            start = rng.uniform(.14, .85)
            speed = rng.uniform(15., 90.)
            analytic = (start-.12)/speed
            if analytic >= 1/60 or speed/60 > 1:
                continue
            result = predict((0.,start,0.), (0.,-speed,0.))
            self.assertIsNotNone(result, (start,speed))
            self.assertAlmostEqual(result[0], analytic, delta=3e-5)
            successes += 1
        self.assertGreater(successes, 130)

    def test_sweep_horizon_safely_expands_current_face_aabbs(self):
        rng = random.Random(77)
        accepted = 0
        for _ in range(440):
            d = rng.uniform(.14, 1.5)
            speed = rng.uniform(15, 110)
            p = (0., d, 0.)
            result = predict(p, (0.,-speed,0.))
            if result is not None:
                self.assertTrue(point_over_aabb(p, FACE, 1. + .12))
                accepted += 1
        self.assertGreater(accepted, 60)
        self.assertFalse(point_over_aabb((0.,1.30,0.), FACE, 1.12))

    def test_four_particle_contact_momentum_and_pins(self):
        weights = (.2,.3,.5)
        inv = (2.,1.,3.,0.)
        effective = inv[0]+sum(w*w*m for w,m in zip(weights,inv[1:]))
        impulse = 35/effective
        changes = [impulse*inv[0]] + [-impulse*w*m for w,m in zip(weights,inv[1:])]
        self.assertEqual(changes[-1], 0.)
        self.assertAlmostEqual(sum(x/m for x,m in zip(changes,inv) if m>0), 0., places=12)
        self.assertIn("point.mVelocity += impulse * point.mInvMass;", self.solver)
        self.assertIn("a.mVelocity -= impulse * (u * a.mInvMass);", self.solver)

    def test_default_off_and_both_bvh_and_linear_broadphase_paths(self):
        self.assertIn("inline static bool soft_body_self_speculative_vertex_face_ccd = false;",self.header)
        self.assertIn('simulation/soft_body_self_speculative_vertex_face_ccd"), false',self.settings)
        self.assertIn("soft_body_self_speculative_vertex_face_ccd = GLOBAL_GET(",self.settings)
        self.assertIn("const bool swept_self_vertex_face_ccd = JoltProjectSettings::soft_body_self_speculative_vertex_face_ccd &&",self.solver)
        self.assertIn("const float candidate_radius = radius +",self.solver)
        self.assertIn("query_soft_face_bvh(r_scratch.bvh.entries, r_scratch.bvh.nodes, point_position,",self.solver)
        self.assertIn("candidate_radius, r_budget, r_scratch.bvh.candidates",self.solver)
        self.assertIn("soft_face_aabb_overlaps_point(min_bound, max_bound, point_position, candidate_radius)",self.solver)
        self.assertIn("const uint32_t candidate_count = use_bvh ?",self.solver)
        self.assertIn("MAX_SOFT_SELF_CONTACT_FACES = 1024",self.src)

    def test_predictor_is_bound_by_relative_corner_speeds_and_budget(self):
        self.assertIn("MAX_SOFT_SELF_VERTEX_FACE_SWEEP_ITERATIONS = 16",self.src)
        self.assertIn("p_point_velocity - p_va",self.predictor)
        self.assertIn("p_point_velocity - p_vb",self.predictor)
        self.assertIn("p_point_velocity - p_vc",self.predictor)
        self.assertIn("travel_bound > p_max_sweep",self.predictor)
        self.assertIn("iteration < MAX_SOFT_SELF_VERTEX_FACE_SWEEP_ITERATIONS && r_budget > 0",self.predictor)
        self.assertIn("--r_budget; // One extra face distance evaluation",self.predictor)
        self.assertIn("closest_soft_triangle_point(point_at_time, a_at_time, b_at_time, c_at_time",self.predictor)
        self.assertIn("time + advance > p_step",self.predictor)
        self.assertIn("approach_speed >= -1.0e-6f",self.predictor)

    def test_topology_filtering_and_future_projection_exclusion(self):
        self.assertLess(self.solver.index("soft_self_is_neighbor(i, face,"), self.solver.index("predict_soft_self_vertex_face_sweep("))
        self.assertIn("!predict_soft_self_vertex_face_sweep(",self.solver)
        self.assertIn("r_budget,",self.solver)
        self.assertIn("if (!swept_contact && r_scratch.position_projection_ready)",self.solver)
        self.assertIn("const float recovery_speed = swept_contact ? 0.0f :",self.solver)
        self.assertIn("swept_contact ? JoltProjectSettings::soft_body_soft_ccd_max_correction_speed",self.solver)
        self.assertIn("const float distance = swept_contact ? radius :",self.solver)
        self.assertIn("swept_normal",self.solver)
        self.assertIn("const float normal_impulse = correction / inverse_mass_sum;",self.solver)

    def test_previous_contact_paths_are_preserved(self):
        self.assertIn("resolve_soft_body_self_edge_contacts(",self.src)
        self.assertIn("static bool refit_soft_self_edge_bvh(",self.src)
        self.assertIn("static void apply_soft_self_position_projection(",self.src)
        self.assertIn("static bool predict_soft_edge_edge_sweep(",self.src)
        self.assertIn("static bool predict_soft_vertex_face_sweep(",self.src)
        self.assertIn("soft_body_self_contact_max_checks",self.src)

    def test_native_fixture_isolated_self_vf(self):
        project = PROJECT.read_text(encoding="utf-8")
        native = NATIVE.read_text(encoding="utf-8")
        self.assertIn("soft_body_self_speculative_vertex_face_ccd=true",project)
        self.assertIn("soft_body_soft_contacts=false",project)
        self.assertIn("soft_body_self_edge_contacts=false",project)
        self.assertIn("soft_body_self_position_projection=false",project)
        self.assertIn("soft_body_soft_contact_recovery=0.0",project)
        self.assertIn("soft_body_apply_point_impulse",native)
        self.assertIn("_mesh(8.0, true)",native)
        self.assertIn("PASS: Jolt swept self vertex-face CCD versus unopposed control",native)


if __name__=="__main__":
    unittest.main()
