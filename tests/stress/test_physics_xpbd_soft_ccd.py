"""Reference numeric and source tests for swept soft-body vertex/face CCD.

These tests verify cubic roots, moving faces, impact witnesses, unilateral
XPBD projection, and opt-in BVH integration. A compiled engine is required
for the paired stress test physics_soft_body_ccd_3d.gd.
"""

import math
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
STRESS = ROOT / "tests/stress"


def add(a, b):
    return tuple(x + y for x, y in zip(a, b))


def sub(a, b):
    return tuple(x - y for x, y in zip(a, b))


def mul(a, k):
    return tuple(x * k for x in a)


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def cross(a, b):
    return (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2],
            a[0]*b[1]-a[1]*b[0])


def lerp(a, b, t):
    return add(a, mul(sub(b, a), t))


def cubic_coefficients(p0, p1, a0, a1, b0, b1, c0, c1):
    v0, dv = sub(p0, a0), sub(sub(p1, p0), sub(a1, a0))
    u0, du = sub(b0, a0), sub(sub(b1, b0), sub(a1, a0))
    w0, dw = sub(c0, a0), sub(sub(c1, c0), sub(a1, a0))
    n0 = cross(u0, w0)
    n1 = add(cross(du, w0), cross(u0, dw))
    n2 = cross(du, dw)
    return (dot(v0, n0),
            dot(dv, n0) + dot(v0, n1),
            dot(dv, n1) + dot(v0, n2),
            dot(dv, n2))


def cubic_roots_in_step(coeffs):
    factor = max(map(abs, coeffs))
    if factor == 0:
        return []
    c0, c1, c2, c3 = (v/factor for v in coeffs)
    def evaluate(t):
        return ((c3*t+c2)*t+c1)*t+c0
    cuts = [0.]
    if abs(c3) > 1.e-12:
        discriminant = c2*c2-3*c3*c1
        if discriminant > 0:
            root = math.sqrt(discriminant)
            cuts.extend(t for t in ((-c2-root)/(3*c3), (-c2+root)/(3*c3))
                        if 0 < t < 1)
    elif abs(c2) > 1.e-12:
        turn = -c1/(2*c2)
        if 0 < turn < 1:
            cuts.append(turn)
    cuts = sorted(cuts) + [1.]
    crossings = []
    for left, right in zip(cuts[:-1], cuts[1:]):
        a, b = evaluate(left), evaluate(right)
        if a*b >= 0:
            continue
        positive = a > 0
        for _ in range(24):
            middle = .5*(left+right)
            if (evaluate(middle) > 0) == positive:
                left = middle
            else:
                right = middle
        crossings.append(.5*(left+right))
    return crossings


def face_witness(point, a, b, c):
    u, v, rel = sub(b, a), sub(c, a), sub(point, a)
    n = cross(u, v)
    norm = math.sqrt(dot(n, n))
    if norm <= 1e-8:
        return None
    n = mul(n, 1/norm)
    distance = dot(rel, n)
    projection = sub(rel, mul(n, distance))
    aa, ab, bb = dot(u, u), dot(u, v), dot(v, v)
    au, bu = dot(projection, u), dot(projection, v)
    denominator = aa*bb-ab*ab
    if denominator <= 0:
        return None
    weight_b = (bb*au-ab*bu)/denominator
    weight_c = (aa*bu-ab*au)/denominator
    weight_a = 1-weight_b-weight_c
    if min(weight_a, weight_b, weight_c) < 0 or max(weight_a, weight_b, weight_c) > 1:
        return None
    return n, (weight_a, weight_b, weight_c), distance


def sweep_vertex(p0, p1, a0, a1, b0, b1, c0, c1):
    old_normal = cross(sub(b0, a0), sub(c0, a0))
    if dot(old_normal, old_normal) <= 1e-12:
        return None
    signed_start = dot(sub(p0, a0), old_normal)
    if abs(signed_start) <= 1e-7:
        return None
    side = 1 if signed_start > 0 else -1
    for t in cubic_roots_in_step(cubic_coefficients(p0, p1, a0, a1, b0, b1, c0, c1)):
        witness = face_witness(lerp(p0, p1, t), lerp(a0, a1, t),
                               lerp(b0, b1, t), lerp(c0, c1, t))
        if witness is not None:
            normal, weights, _ = witness
            return t, weights, mul(normal, side)
    return None


def correct_swept(positions, masses, hit, thickness=.12, compliance=1e-6, dt=1/60):
    _, weights, normal = hit
    vertex, a, b, c = positions
    face_point = add(add(mul(a, weights[0]), mul(b, weights[1])), mul(c, weights[2]))
    gap = dot(sub(vertex, face_point), normal)
    factors = [1., -weights[0], -weights[1], -weights[2]]
    effective_mass = sum(m*f*f for m, f in zip(masses, factors))
    alpha = compliance/dt**2
    dl = max(0., (thickness-gap)/(effective_mass+alpha))
    next_points = tuple(add(p, mul(normal, m*f*dl))
                        for p, m, f in zip(positions, masses, factors))
    return next_points, dl


class XPBDSoftCCDContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.helper = (ROOT / "servers/physics_xpbd_soft_ccd.h").read_text(encoding="utf-8")
        cls.cpp = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.cpp").read_text(encoding="utf-8")
        cls.header = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.h").read_text(encoding="utf-8")
        cls.space = (ROOT / "modules/godot_physics_3d/godot_space_3d.cpp").read_text(encoding="utf-8")
        cls.space_h = (ROOT / "modules/godot_physics_3d/godot_space_3d.h").read_text(encoding="utf-8")
        cls.settings = (ROOT / "servers/physics_3d/physics_server_3d.cpp").read_text(encoding="utf-8")

    def test_one_step_crossing_requires_sweep(self):
        a, b, c = (-3., -3., 0.), (3., -3., 0.), (0., 3., 0.)
        hit = sweep_vertex((0., 0., .45), (0., 0., -.75), a, a, b, b, c, c)
        self.assertIsNotNone(hit)
        self.assertAlmostEqual(hit[0], .375, delta=1e-6)
        self.assertAlmostEqual(sum(hit[1]), 1.)
        self.assertEqual(hit[2], (0., 0., 1.))
        self.assertLess(-.75, -.12)

    def test_cubic_stationary_points_find_multiple_crossings(self):
        # Two physical plane crossings can occur even if both ENDPOINTS
        # have the same signed plane distance for a moving/deforming face.
        # (t-0.2)*(t-0.6)*(t-1.2) has roots at 0.2 and 0.6 in [0,1].
        roots = cubic_roots_in_step((-.144, 1.08, -2., 1.))
        self.assertEqual(len(roots), 2)
        self.assertAlmostEqual(roots[0], .2, delta=1e-6)
        self.assertAlmostEqual(roots[1], .6, delta=1e-6)

    def test_moving_face_crosses_stationary_vertex(self):
        point = (0., 0., 0.)
        a0, b0, c0 = (-3., -3., -.45), (3., -3., -.45), (0., 3., -.45)
        delta = (0., 0., 1.2)
        a1, b1, c1 = add(a0, delta), add(b0, delta), add(c0, delta)
        hit = sweep_vertex(point, point, a0, a1, b0, b1, c0, c1)
        self.assertIsNotNone(hit)
        self.assertAlmostEqual(hit[0], .375, delta=1e-6)
        positions, impulse = correct_swept((point, a1, b1, c1), (0., 3., 3., 3.), hit)
        self.assertEqual(positions[0], point)
        face = add(add(mul(positions[1], hit[1][0]), mul(positions[2], hit[1][1])),
                   mul(positions[3], hit[1][2]))
        self.assertLess(face[2], -.11)
        self.assertGreater(impulse, 0.)

    def test_ccd_witness_finds_interior_and_rejects_external_plane(self):
        a, b, c = (-3., -3., 0.), (3., -3., 0.), (0., 3., 0.)
        miss = sweep_vertex((8., 8., .45), (8., 8., -.75), a, a, b, b, c, c)
        self.assertIsNone(miss)
        hit = sweep_vertex((0., 0., .45), (0., 0., -.75), a, a, b, b, c, c)
        positions, impulse = correct_swept(((0., 0., -.75), a, b, c),
                                            (6., 0., 0., 0.), hit)
        self.assertEqual(positions[1:], (a, b, c))
        self.assertGreater(positions[0][2], .11)
        self.assertGreater(impulse, 0.)

    def test_opt_in_config_and_independent_contact_buffer(self):
        self.assertIn('"physics/3d/solver/soft_body_self_collision_ccd"), false);', self.settings)
        self.assertIn("soft_body_self_collision_ccd = false;", self.space_h)
        self.assertIn("is_soft_body_self_collision_ccd_enabled()", self.space_h)
        self.assertIn('GLOBAL_GET("physics/3d/solver/soft_body_self_collision_ccd")', self.space)
        self.assertIn("struct SelfCCDContact", self.header)
        self.assertIn("LocalVector<SelfCCDContact> xpbd_self_ccd_contacts;", self.header)
        self.assertIn("xpbd_self_ccd_contacts.reset();", self.cpp)
        self.assertIn("xpbd_self_contacts.clear();", self.cpp)
        self.assertIn("xpbd_self_ccd_contacts.clear();", self.cpp)
        self.assertIn("const bool swept_ccd = get_space()->is_soft_body_self_collision_ccd_enabled();", self.cpp)

    def test_swept_broadphase_continuous_narrowphase_and_solver(self):
        self.assertIn("update_swept_face_tree(thickness);", self.cpp)
        self.assertIn("swept.expand_to(a->x);", self.cpp)
        self.assertIn("swept.expand_to(b->q);", self.cpp)
        self.assertIn("swept_query.expand_to(node.x);", self.cpp)
        self.assertIn("physics_xpbd_swept_vertex_triangle(", self.cpp)
        self.assertIn("physics_xpbd_solve_swept_vertex_face(", self.cpp)
        self.assertIn("const bool vertex_contacts = !xpbd_self_contacts.is_empty() || !xpbd_self_ccd_contacts.is_empty();", self.cpp)
        self.assertIn("xpbd_self_contacts.size() + xpbd_self_ccd_contacts.size()", self.cpp)
        self.assertIn("face_tree.aabb_query(swept_query, visit_face)", self.cpp)
        self.assertIn("face_tree.aabb_query(AABB(node.x - padding", self.cpp)
        self.assertIn("physics_xpbd_solve_self_collision(node.x", self.cpp)
        self.assertIn("physics_xpbd_solve_edge_collision(", self.cpp)

    def test_cubic_is_bounded_and_xpbd_contacts_are_atomic(self):
        self.assertIn("const double raw_c[4]", self.helper)
        self.assertIn("const double discriminant = c2 * c2 - 3.0 * c3 * c1;", self.helper)
        self.assertIn("for (int j = 0; j < 24; ++j)", self.helper)
        self.assertIn("const Vector3 vertex = p_prev_vertex.lerp(p_curr_vertex, t);", self.helper)
        self.assertIn("physics_xpbd_self_collision_face_projection(", self.helper)
        self.assertIn("const double next_lambda_double = MAX(0.0", self.helper)
        self.assertIn("!next_vertex.is_finite() || !next_a.is_finite()", self.helper)
        self.assertIn("r_vertex = next_vertex;\n\tr_a = next_a;\n\tr_b = next_b;\n\tr_c = next_c;", self.helper)

    def test_real_stress_and_runner_are_registered(self):
        case = "physics_soft_body_ccd_3d"
        self.assertIn(f'"{case}"', (STRESS / "run.py").read_text(encoding="utf-8"))
        self.assertIn(f'"{case}":', (STRESS / "stress.gd").read_text(encoding="utf-8"))
        workload = (STRESS / f"{case}.gd").read_text(encoding="utf-8")
        self.assertIn("soft_body_apply_point_impulse(body, j", workload)
        self.assertIn("var discrete: Dictionary =", workload)
        self.assertIn("var continuous: Dictionary =", workload)
        self.assertIn("continuous.min_z > 0.02", workload)
        self.assertIn('3d/physics_engine="GodotPhysics3D"',
                      (STRESS / "project.godot").read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
