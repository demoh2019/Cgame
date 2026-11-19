"""Conservative advancement for two linearly moving deformable soft-body edges.

Independent reference geometry + source contracts. Does not compile or run C++.
Native regression: jolt_soft_soft_edge_sweep/swept_edges_regression.gd
"""
import math
import random
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "modules/jolt_physics/spaces/jolt_space_3d.cpp"
SETTINGS = ROOT / "modules/jolt_physics/jolt_project_settings.cpp"
HEADER = ROOT / "modules/jolt_physics/jolt_project_settings.h"
SCENE = ROOT / "tests/stress/jolt_soft_soft_edge_sweep/swept_edges_regression.gd"
PROJECT = ROOT / "tests/stress/jolt_soft_soft_edge_sweep/project.godot"


def sub(a, b):
    return tuple(x - y for x, y in zip(a, b))


def add_scaled(a, v, t):
    return tuple(x + y * t for x, y in zip(a, v))


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def magnitude(v):
    return math.sqrt(dot(v, v))


def closest_segments(p0, p1, q0, q1):
    """Independent Ericson segment/segment closest-point reference."""
    d1, d2, r = sub(p1, p0), sub(q1, q0), sub(p0, q0)
    a, e = dot(d1, d1), dot(d2, d2)
    if not math.isfinite(a) or not math.isfinite(e) or min(a, e) <= 1e-12:
        return None
    b, c, f = dot(d1, d2), dot(d1, r), dot(d2, r)
    denominator = a * e - b * b
    if not all(math.isfinite(x) for x in (denominator, c, f)):
        return None
    s = max(0., min(1., (b * f - c * e) / denominator)) if denominator > 1e-12 else 0.
    t = (b * s + f) / e
    if t < 0:
        t, s = 0., max(0., min(1., -c / a))
    elif t > 1:
        t, s = 1., max(0., min(1., (b - c) / a))
    if not math.isfinite(s) or not math.isfinite(t):
        return None
    return s, t, add_scaled(p0, d1, s), add_scaled(q0, d2, t)


def predict(p0, p1, q0, q1, vp0, vp1, vq0, vq1,
            dt=1 / 60, radius=.14, max_sweep=4, budget=32768):
    """Return (time, s, t, contact_normal, spent_budget) or None.

    Sample the closest distance after every conservative time increment,
    accounting for the max relative endpoint velocity. Matches the C++
    algorithm's 16-iteration and available-work bounds.
    """
    if dt <= 0 or radius <= 0 or max_sweep <= 0:
        return None
    speed_bound = max(magnitude(sub(va, vb)) for va in (vp0, vp1) for vb in (vq0, vq1))
    if not math.isfinite(speed_bound) or speed_bound <= 1e-6 or speed_bound * dt > max_sweep:
        return None
    time = 0.
    spent = 0
    for _ in range(min(16, budget)):
        spent += 1
        positions = [add_scaled(p, vel, time) for p, vel in
                     zip((p0, p1, q0, q1), (vp0, vp1, vq0, vq1))]
        closest = closest_segments(*positions)
        if closest is None:
            return None
        s, t, a, b = closest
        gap = sub(b, a)
        distance = magnitude(gap)
        if not math.isfinite(distance):
            return None
        if time > 0 and distance <= radius + 1e-4:
            va = tuple((1-s)*vp0[i] + s*vp1[i] for i in range(3))
            vb = tuple((1-t)*vq0[i] + t*vq1[i] for i in range(3))
            relative = sub(vb, va)
            if distance > 1e-6:
                normal = tuple(x / distance for x in gap)
            elif magnitude(relative) > 1e-6:
                normal = tuple(-x / magnitude(relative) for x in relative)
            else:
                return None
            if dot(relative, normal) >= -1e-6:
                return None
            return time, s, t, normal, spent
        if distance <= radius:
            return None
        advance = (distance - radius) / speed_bound
        if not math.isfinite(advance) or advance <= 1e-8 * dt or time + advance > dt:
            return None
        time += advance
    return None


def horizontal(z):
    return (-.9, 2., z), (.9, 2., z)


def vertical():
    return (0., 1.1, 0.), (0., 2.9, 0.)


ZERO = (0., 0., 0.)


class SoftEdgeSweepReferenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = SOURCE.read_text(encoding="utf-8")
        cls.settings = SETTINGS.read_text(encoding="utf-8")
        cls.header = HEADER.read_text(encoding="utf-8")
        cls.prediction = cls.source.split("static bool predict_soft_edge_edge_sweep(", 1)[1].split(
            "static void resolve_soft_soft_edge_edge_contacts(", 1
        )[0]
        cls.solver = cls.source.split("static void resolve_soft_soft_edge_edge_contacts(", 1)[1].split(
            "static void clear_pending_index(", 1
        )[0]
        cls.prestep = cls.source.split("void JoltSpace3D::_pre_step(float p_step) {", 1)[1].split(
            "void JoltSpace3D::_post_step(float p_step) {", 1
        )[0]

    def test_fast_crossing_segment_detected_before_interpenetration(self):
        p0, p1 = horizontal(-.38)
        q0, q1 = vertical()
        result = predict(p0, p1, q0, q1, (0, 0, 35), (0, 0, 35), ZERO, ZERO)
        self.assertIsNotNone(result)
        time, s, t, normal, work = result
        self.assertAlmostEqual(time, (.38 - .14) / 35, places=6)
        self.assertAlmostEqual(s, .5, places=5)
        self.assertAlmostEqual(t, .5, places=5)
        self.assertGreater(normal[2], .99)
        self.assertLessEqual(work, 16)
        self.assertGreater(math.dist(p0, q0), .14)

    def test_swapping_soft_bodies_flips_normal_but_not_toi(self):
        p0, p1 = horizontal(-.38)
        q0, q1 = vertical()
        forward = predict(p0, p1, q0, q1, (0, 0, 35), (0, 0, 35), ZERO, ZERO)
        backwards = predict(q0, q1, p0, p1, ZERO, ZERO, (0, 0, 35), (0, 0, 35))
        self.assertIsNotNone(backwards)
        self.assertAlmostEqual(forward[0], backwards[0])
        self.assertLess(dot(forward[3], backwards[3]), -.99)

    def test_parallel_edges_and_moving_target(self):
        p0, p1 = (-1., .4, 0.), (1., .4, 0.)
        q0, q1 = (-1., 0., 0.), (1., 0., 0.)
        hit = predict(p0, p1, q0, q1, (0, -30, 0), (0, -30, 0), ZERO, ZERO)
        self.assertIsNotNone(hit)
        self.assertAlmostEqual(hit[0], (.4-.14)/30, places=5)
        moving_target = predict(p0, p1, q0, q1, ZERO, ZERO,
                                (0, 30, 0), (0, 30, 0))
        self.assertIsNotNone(moving_target)
        self.assertAlmostEqual(moving_target[0], hit[0])

    def test_outgoing_zero_speed_degenerate_and_no_contact(self):
        p0, p1 = horizontal(-.38)
        q0, q1 = vertical()
        self.assertIsNone(predict(p0, p1, q0, q1, ZERO, ZERO, ZERO, ZERO))
        self.assertIsNone(predict(p0, p1, q0, q1, (0, 0, -35), (0, 0, -35), ZERO, ZERO))
        self.assertIsNone(predict(p0, p0, q0, q1, (0, 0, 35), (0, 0, 35), ZERO, ZERO))
        self.assertIsNone(predict(p0, p1, (4, 4, 0), (4, 5, 0),
                                  (0, 0, 35), (0, 0, 35), ZERO, ZERO))
        self.assertIsNone(predict(p0, p1, q0, q1,
                                  (float("nan"), 0, 35), (0, 0, 35), ZERO, ZERO))

    def test_horizon_and_budget_rejection(self):
        p0, p1 = horizontal(-.38)
        q0, q1 = vertical()
        self.assertIsNone(predict(p0, p1, q0, q1,
                                  (0, 0, 35), (0, 0, 35), ZERO, ZERO, max_sweep=.5))
        self.assertIsNone(predict(p0, p1, q0, q1,
                                  (0, 0, 35), (0, 0, 35), ZERO, ZERO, budget=1))
        self.assertIsNotNone(predict(p0, p1, q0, q1,
                                     (0, 0, 35), (0, 0, 35), ZERO, ZERO, budget=4))
        self.assertIsNone(predict(p0, p1, q0, q1,
                                  (0, 0, 35), (0, 0, 35), ZERO, ZERO, dt=0))

    def test_randomized_linear_crossings_versus_analytic_toi(self):
        rng = random.Random(41)
        q0, q1 = vertical()
        checked = 0
        for _ in range(150):
            distance = rng.uniform(.16, .85)
            speed = rng.uniform(20., 100.)
            if (distance - .14) / speed >= 1/60:
                continue
            p0, p1 = horizontal(-distance)
            result = predict(p0, p1, q0, q1,
                             (0, 0, speed), (0, 0, speed), ZERO, ZERO, max_sweep=4)
            self.assertIsNotNone(result, (distance, speed))
            self.assertAlmostEqual(result[0], (distance - .14) / speed, delta=3e-5)
            checked += 1
        self.assertGreater(checked, 80)

    def test_mass_weighted_impulses_conserve_four_endpoint_momenta(self):
        s, t = .25, .6
        inv_mass = [1., 2., 3., 4.]
        weights = [1-s, s, 1-t, t]
        effective = sum(w * w * mass for w, mass in zip(weights, inv_mass))
        impulse = 23. / effective
        changes = [(-1 if i < 2 else 1) * inv_mass[i] * weights[i] * impulse for i in range(4)]
        momentum = sum(change / mass for change, mass in zip(changes, inv_mass))
        self.assertAlmostEqual(momentum, 0.)
        self.assertIn("a0.mVelocity -= local_impulse_a * (wa0 * a0.mInvMass)", self.solver)
        self.assertIn("b1.mVelocity += local_impulse_b * (wb1 * b1.mInvMass)", self.solver)

    def test_new_mode_is_opt_in_and_uses_existing_bounds(self):
        self.assertIn("inline static bool soft_body_soft_speculative_edge_ccd = false;", self.header)
        self.assertIn('soft_body_soft_speculative_edge_ccd"), false', self.settings)
        self.assertIn("soft_body_soft_speculative_edge_ccd = GLOBAL_GET(", self.settings)
        self.assertIn("JoltProjectSettings::soft_body_soft_speculative_edge_ccd &&", self.solver)
        self.assertIn("const float candidate_radius = radius +", self.solver)
        self.assertIn("const float max_correction = swept_contact ?", self.solver)
        self.assertIn("const float recovery_speed = swept_contact ? 0.0f", self.solver)
        self.assertIn("resolve_soft_soft_vertex_face_contacts(*jolt_a", self.prestep)
        self.assertIn("resolve_soft_soft_particle_contacts(*jolt_a", self.prestep)
        self.assertIn("bounds_a.intersects(object_b->get_bounds().grow(broadphase_margin))", self.prestep)

    def test_conservative_advancement_charges_each_iteration(self):
        self.assertIn("MAX_SOFT_EDGE_SWEEP_ITERATIONS = 16", self.source)
        self.assertIn("SOFT_EDGE_SWEEP_DISTANCE_TOLERANCE", self.source)
        self.assertIn("--r_budget;", self.prediction)
        self.assertIn("iteration < MAX_SOFT_EDGE_SWEEP_ITERATIONS && r_budget > 0", self.prediction)
        self.assertIn("(distance - p_radius) / speed_bound", self.prediction)
        self.assertIn("travel_bound > p_max_sweep", self.prediction)
        self.assertIn("max_relative_speed_sq", self.prediction)
        self.assertIn("relative_velocity.Dot(normal)", self.solver)
        self.assertIn("edge_budget = edge_contacts ? particle_budget / 2 : 0;", self.prestep)

    def test_native_scene_moving_edges_and_masked_control(self):
        project = PROJECT.read_text(encoding="utf-8")
        native = SCENE.read_text(encoding="utf-8")
        self.assertIn("soft_body_soft_speculative_edge_ccd=true", project)
        self.assertIn("soft_body_soft_speculative_ccd=false", project)
        self.assertIn("soft_body_soft_ccd_max_sweep=4.0", project)
        self.assertIn("Vector3(0.0, 0.0, 35.0)", native)
        self.assertIn("masked_travel_z", native)
        self.assertIn("PASS: Jolt conservative swept soft-edge contacts and collision filters", native)


if __name__ == "__main__":
    unittest.main()
