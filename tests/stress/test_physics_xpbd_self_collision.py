"""XPBD soft vertex/face self-contact numerical and source regressions.

These contracts do not replace compiling GodotPhysics3D. The companion
GDScript scenario checks separation and topological exclusion at runtime.
"""

import math
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
STRESS = ROOT / "tests/stress"


def sub(a, b):
    return tuple(x - y for x, y in zip(a, b))


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def cross(a, b):
    return (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2],
            a[0]*b[1]-a[1]*b[0])


def norm(a):
    return math.sqrt(dot(a, a))


def projected_face(point, a, b, c):
    ab, ac = sub(b, a), sub(c, a)
    normal = cross(ab, ac)
    n = norm(normal)
    if n < 1e-9:
        return None
    normal = tuple(q/n for q in normal)
    relative = sub(point, a)
    distance = dot(relative, normal)
    projected = sub(relative, tuple(distance*x for x in normal))
    d00, d01, d11 = dot(ab, ab), dot(ab, ac), dot(ac, ac)
    d20, d21 = dot(projected, ab), dot(projected, ac)
    denominator = d00*d11 - d01*d01
    if denominator <= 0:
        return None
    v = (d11*d20-d01*d21)/denominator
    w = (d00*d21-d01*d20)/denominator
    u = 1-v-w
    if min(u, v, w) < 0 or max(u, v, w) > 1:
        return None
    return normal, (u, v, w), distance


def project_step(positions, inverse_masses, thickness, compliance, dt,
                 side, lagrange=0.):
    hit = projected_face(*positions)
    if hit is None:
        return positions, lagrange
    normal, bary, distance = hit
    weight = inverse_masses[0] + sum(inverse_masses[i+1]*bary[i]*bary[i]
                                     for i in range(3))
    if weight <= 0 or abs(distance) > thickness*2:
        return positions, lagrange
    alpha = compliance / (dt*dt)
    delta = (thickness-side*distance-alpha*lagrange) / (weight+alpha)
    next_lambda = max(0., lagrange+delta)
    impulse = next_lambda-lagrange
    normal = tuple(n*side for n in normal)
    next_points = []
    for i, point in enumerate(positions):
        factor = inverse_masses[i] * impulse * (1 if i == 0 else -bary[i-1])
        next_points.append(tuple(point[k]+factor*normal[k] for k in range(3)))
    return tuple(next_points), next_lambda


class XPBDSelfCollisionContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.helper = (ROOT / "servers/physics_xpbd_self_collision.h").read_text(encoding="utf-8")
        cls.cpp = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.cpp").read_text(encoding="utf-8")
        cls.header = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.h").read_text(encoding="utf-8")
        cls.space = (ROOT / "modules/godot_physics_3d/godot_space_3d.cpp").read_text(encoding="utf-8")
        cls.space_header = (ROOT / "modules/godot_physics_3d/godot_space_3d.h").read_text(encoding="utf-8")
        cls.settings = (ROOT / "servers/physics_3d/physics_server_3d.cpp").read_text(encoding="utf-8")

    def test_barycentrics_for_interior_and_reject_exterior_or_degenerate(self):
        a, b, c = (-2., -2., 0.), (2., -2., 0.), (0., 2., 0.)
        hit = projected_face((0., 0., .02), a, b, c)
        self.assertIsNotNone(hit)
        normal, bary, dist = hit
        self.assertAlmostEqual(sum(bary), 1.)
        self.assertAlmostEqual(dist, .02)
        self.assertEqual(normal, (0., 0., 1.))
        self.assertIsNone(projected_face((7., 7., .02), a, b, c))
        self.assertIsNone(projected_face((0., 0., 0.), a, a, a))

    def test_two_layers_separate_without_moving_pinned_face(self):
        initial = ((0., 0., .02), (-2., -2., 0.), (2., -2., 0.), (0., 2., 0.))
        positions = initial
        lam = 0.
        for _ in range(4):
            positions, lam = project_step(positions, (6., 0., 0., 0.),
                                          .12, 1e-6, 1./60., 1, lam)
        self.assertEqual(positions[1:], initial[1:])
        self.assertGreater(positions[0][2], .11)
        self.assertGreaterEqual(lam, 0.)

    def test_negative_previous_side_pushes_back_across_face(self):
        original = ((0., 0., .01), (-2., -2., 0.), (2., -2., 0.), (0., 2., 0.))
        out, lam = project_step(original, (2., 0., 0., 0.),
                                .12, 1e-6, 1./60., -1)
        self.assertLess(out[0][2], -.1)
        self.assertTrue(lam > 0)

    def test_unilateral_constraint_does_not_attract_separate_layers(self):
        original = ((0., 0., .25), (-2., -2., 0.), (2., -2., 0.), (0., 2., 0.))
        out, lam = project_step(original, (1., 0., 0., 0.),
                                .12, 1e-6, 1./60., 1)
        self.assertEqual(out, original)
        self.assertEqual(lam, 0.)

    def test_opt_in_and_bvh_filtering(self):
        self.assertIn('"physics/3d/solver/soft_body_self_collision_thickness"', self.settings)
        self.assertIn('"physics/3d/solver/soft_body_self_collision_compliance"', self.settings)
        self.assertIn('"physics/3d/solver/soft_body_self_collision_max_contacts_per_vertex"', self.settings)
        self.assertIn("soft_body_self_collision_thickness = 0.0;", self.space_header)
        self.assertIn('GLOBAL_GET("physics/3d/solver/soft_body_self_collision_thickness")', self.space)
        self.assertIn("LocalVector<SelfCollisionContact> xpbd_self_contacts;", self.header)
        self.assertIn("HashSet<uint64_t> xpbd_self_neighbor_edges;", self.header)
        self.assertIn("void GodotSoftBody3D::initialize_self_collision_topology()", self.cpp)
        self.assertIn("void GodotSoftBody3D::solve_self_collisions(real_t p_delta)", self.cpp)
        self.assertIn("face_tree.aabb_query(AABB(node.x - padding", self.cpp)
        self.assertIn("xpbd_self_neighbor_edges.has(_soft_body_edge_key(node_id, a))", self.cpp)
        self.assertIn("physics_xpbd_self_collision_face_projection(", self.cpp)
        self.assertIn("physics_xpbd_solve_self_collision(node.x,", self.cpp)
        self.assertIn("const uint32_t global_limit = uint32_t(MIN(uint64_t(65536)", self.cpp)
        self.assertIn("const int contact_iterations = MIN(MAX(iteration_count, 1), 4);", self.cpp)
        self.assertIn("xpbd_self_neighbor_edges.reset();", self.cpp)

    def test_solver_is_safe_and_atomic(self):
        self.assertIn("physics_xpbd_self_collision_face_projection(", self.helper)
        self.assertIn("physics_xpbd_solve_self_collision(", self.helper)
        self.assertIn("u < 0.0 || v < 0.0 || w < 0.0", self.helper)
        self.assertIn("p_inv_vertex < 0.0", self.helper)
        self.assertIn("const double next_lambda_double = MAX(0.0", self.helper)
        self.assertIn("if (!next_vertex.is_finite() || !next_a.is_finite()", self.helper)
        self.assertIn("r_vertex = next_vertex;\n\tr_a = next_a;\n\tr_b = next_b;\n\tr_c = next_c;", self.helper)
        self.assertIn("if (Math::abs(distance) > p_thickness * real_t(2.0))", self.helper)

    def test_stress_registration_and_adjacency_case(self):
        name = "physics_soft_body_self_collision_3d"
        runner = (STRESS / "run.py").read_text(encoding="utf-8")
        dispatcher = (STRESS / "stress.gd").read_text(encoding="utf-8")
        workload = (STRESS / (name + ".gd")).read_text(encoding="utf-8")
        self.assertIn(f'"{name}"', runner)
        self.assertIn(f'"{name}":', dispatcher)
        self.assertIn("var repelled: Dictionary =", workload)
        self.assertIn("var adjacent: Dictionary =", workload)
        self.assertIn("repelled.mean_z > baseline.mean_z + 0.04", workload)
        self.assertIn("adjacent.mean_z < 0.04", workload)
        self.assertIn('3d/physics_engine="GodotPhysics3D"',
                      (STRESS / "project.godot").read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
