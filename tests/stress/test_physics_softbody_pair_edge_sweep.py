"""Reference contracts for GodotPhysics soft-soft swept structural edge CCD.

Checks independent linear-trajectory TOI examples and mass-weighted two-way
projection. Source wiring checks keep the opt-in zero-cost default intact.
Python models are not a substitute for compiling and running the C++ engine.
"""
import math
from pathlib import Path
import random
import unittest

ROOT = Path(__file__).resolve().parents[2]


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def diff(a, b):
    return tuple(x - y for x, y in zip(a, b))


def lerp(a, b, t):
    return tuple(x * (1 - t) + y * t for x, y in zip(a, b))


def closest_edges(a, b, c, d):
    """Unclamped interior closest points, independent double-precision reference."""
    ab, cd, r = diff(b, a), diff(d, c), diff(a, c)
    aa, bb, cc = dot(ab, ab), dot(ab, cd), dot(cd, cd)
    dd, ee = dot(ab, r), dot(cd, r)
    det = aa * cc - bb * bb
    if det <= 1e-10 * aa * cc or min(aa, cc) <= 1e-20:
        return None
    s = (bb * ee - cc * dd) / det
    t = (aa * ee - bb * dd) / det
    if not .001 < s < .999 or not .001 < t < .999:
        return None
    p, q = lerp(a, b, s), lerp(c, d, t)
    v = diff(p, q)
    distance = math.sqrt(dot(v, v))
    if distance <= 1e-12:
        return None
    normal = tuple(x / distance for x in v)
    return s, t, normal, distance


def swept_edges(previous, current, radius):
    if radius <= 0:
        return None
    motion = [diff(current[i], previous[i]) for i in range(4)]
    speed_bound = max(math.dist(motion[i], motion[j])
                      for i in range(2) for j in range(2, 4))
    if speed_bound <= 0:
        return None
    time = 0.0
    tolerance = max(radius * 1e-4, 1e-7)
    for _ in range(24):
        p = [lerp(previous[i], current[i], time) for i in range(4)]
        closest = closest_edges(*p)
        if closest is None:
            return None
        s, t, normal, distance = closest
        if time > 0 and distance <= radius + tolerance:
            relative_motion = diff(lerp(motion[0], motion[1], s),
                                   lerp(motion[2], motion[3], t))
            if dot(relative_motion, normal) >= -1e-8 * speed_bound:
                return None
            return time, s, t, normal
        if distance <= radius:
            return None
        advance = (distance - radius) / speed_bound
        if advance <= 1e-9 or time + advance >= 1:
            return None
        time += advance
    return None


def project_swept(current, inverse_masses, hit, thickness, compliance, delta):
    toi, s, t, normal = hit
    weights = (1 - s, s, -(1 - t), -t)
    mass = sum(inv * weight * weight
               for inv, weight in zip(inverse_masses, weights))
    if mass <= 0:
        return None
    relative = tuple(sum(weights[i] * current[i][axis] for i in range(4))
                     for axis in range(3))
    separation = dot(relative, normal)
    impulse = max(0.0, (thickness - separation) /
                  (mass + compliance / (delta * delta)))
    corrections = [tuple(normal[k] * impulse * weights[i] * inverse_masses[i]
                         for k in range(3)) for i in range(4)]
    after = [tuple(current[i][k] + corrections[i][k] for k in range(3))
             for i in range(4)]
    return after, corrections, impulse


class SoftPairEdgeCCDContracts(unittest.TestCase):
    def test_3000_fast_crossings_analytic_toi(self):
        rng = random.Random(0xEDEC0DE)
        for _ in range(3000):
            radius = rng.uniform(.002, .15)
            start_distance = rng.uniform(radius + .01, 1.5)
            end_distance = rng.uniform(radius + .01, .8)
            # First edge moves through an independently moving second edge.
            first_start_z = rng.uniform(-1., 1.)
            second_start_z = first_start_z + start_distance
            second_shift_z = rng.uniform(-.5, .5)
            first_shift_z = second_shift_z + start_distance + end_distance
            first_end_z = first_start_z + first_shift_z
            second_end_z = second_start_z + second_shift_z
            previous = ((-1., 0., first_start_z), (1., 0., first_start_z),
                        (0., -1., second_start_z), (0., 1., second_start_z))
            current = ((-1., 0., first_end_z), (1., 0., first_end_z),
                       (0., -1., second_end_z), (0., 1., second_end_z))
            hit = swept_edges(previous, current, radius)
            self.assertIsNotNone(hit, (radius, start_distance, end_distance))
            expected = (start_distance - radius) / (start_distance + end_distance)
            self.assertAlmostEqual(hit[0], expected, delta=1e-6)
            self.assertAlmostEqual(hit[1], .5, delta=1e-9)
            self.assertAlmostEqual(hit[2], .5, delta=1e-9)
            self.assertLess(hit[3][2], -.99)
            # AABB union of both endpoints always overlaps in this crossing.
            a_min = min(first_start_z, first_end_z) - radius
            a_max = max(first_start_z, first_end_z) + radius
            b_min = min(second_start_z, second_end_z) - radius
            b_max = max(second_start_z, second_end_z) + radius
            self.assertLessEqual(max(a_min, b_min), min(a_max, b_max))

    def test_conservation_3000_free_particles(self):
        rng = random.Random(0xD00D)
        for _ in range(3000):
            inv = [rng.uniform(.1, 4) for _ in range(4)]
            current = [(-1., 0., .28), (1., 0., .28),
                       (0., -1., 0.), (0., 1., 0.)]
            hit = (.4, .5, .5, (0., 0., -1.))
            result = project_swept(current, inv, hit, .1, 0.0, .02)
            self.assertIsNotNone(result)
            after, displacements, lam = result
            self.assertGreater(lam, 0)
            self.assertAlmostEqual(sum(displacements[i][2] / inv[i]
                                       for i in range(4)), 0., delta=1e-12)
            self.assertAlmostEqual(
                sum(after[i][2] * (-1 if i >= 2 else 1) * .5
                    for i in range(4)), -.1, delta=1e-12)
            for i in range(4):
                self.assertTrue(all(math.isfinite(x) for x in displacements[i]))

    def test_pinned_face_and_missed_crossing(self):
        previous = ((-1., 0., -.38), (1., 0., -.38),
                    (0., -1., 0.), (0., 1., 0.))
        current = ((-1., 0., .28), (1., 0., .28),
                   (0., -1., 0.), (0., 1., 0.))
        hit = swept_edges(previous, current, .1)
        self.assertIsNotNone(hit)
        after, displacements, _ = project_swept(current, (1., 1., 0., 0.),
                                                hit, .1, 0.0, .02)
        self.assertAlmostEqual(after[0][2], -.1)
        self.assertAlmostEqual(after[1][2], -.1)
        self.assertEqual(after[2], current[2])
        self.assertEqual(after[3], current[3])
        moving_away = ((-1., 0., -.8), (1., 0., -.8),
                       (0., -1., 0.), (0., 1., 0.))
        self.assertIsNone(swept_edges(previous, moving_away, .1))
        self.assertIsNone(swept_edges(current, current, .1))

    def test_config_and_solver_wiring(self):
        server = (ROOT / "servers/physics_3d/physics_server_3d.cpp").read_text()
        space_h = (ROOT / "modules/godot_physics_3d/godot_space_3d.h").read_text()
        space_cpp = (ROOT / "modules/godot_physics_3d/godot_space_3d.cpp").read_text()
        soft = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.cpp").read_text()
        helper = (ROOT / "servers/physics_softbody_pair_edge_sweep.h").read_text()
        self.assertIn('"physics/3d/solver/soft_body_pair_collision_edge_ccd"), false', server)
        self.assertIn('bool soft_body_pair_collision_edge_ccd = false;', space_h)
        self.assertIn('soft_body_pair_collision_edge_ccd = GLOBAL_GET(', space_cpp)
        self.assertIn('is_soft_body_pair_collision_ccd_enabled()', soft)
        self.assertIn('update_pair_edge_tree(p_thickness, swept_ccd)', soft)
        self.assertIn('query.expand_to(pair_ccd_previous[edge.a]);', soft)
        self.assertIn('p_other.pair_ccd_previous[other.a]', soft)
        self.assertIn('physics_softbody_swept_edge_edge(', soft)
        self.assertIn('physics_softbody_solve_swept_pair_edges(', soft)
        self.assertIn('const uint32_t max_sweep_candidates =', soft)
        self.assertIn('for (int iteration = 0; iteration < 24; ++iteration)', helper)
        self.assertIn('(double(distance) - double(p_thickness)) / speed_bound', helper)
        self.assertIn('next_positions[i] = Vector3(', helper)
        self.assertLess(soft.index('swept_contacts.push_back(contact);'),
                        soft.index('physics_softbody_solve_swept_pair_edges('))


if __name__ == "__main__":
    unittest.main()
