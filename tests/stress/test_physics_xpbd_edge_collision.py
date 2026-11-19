"""Analytical and source contracts for optional cloth edge-edge XPBD collision.

This test verifies isolated numerical contact math and structural integration.
The companion GDScript stress case checks actual Cgame runtime behavior.
"""

import math
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
STRESS = ROOT / "tests/stress"


def sub(a, b):
    return tuple(x-y for x, y in zip(a, b))


def dot(a, b):
    return sum(x*y for x, y in zip(a, b))


def add(a, b):
    return tuple(x+y for x, y in zip(a, b))


def mul(a, k):
    return tuple(x*k for x in a)


def cross(a, b):
    return (a[1]*b[2]-a[2]*b[1],
            a[2]*b[0]-a[0]*b[2],
            a[0]*b[1]-a[1]*b[0])


def closest_interior(points):
    a, b, c, d = points
    ab, cd, r = sub(b, a), sub(d, c), sub(a, c)
    aa, bb, cc = dot(ab, ab), dot(ab, cd), dot(cd, cd)
    dd, ee = dot(ab, r), dot(cd, r)
    den = aa*cc-bb*bb
    if aa <= 1e-12 or cc <= 1e-12 or den <= 1e-5*aa*cc:
        return None
    s, t = (bb*ee-cc*dd)/den, (aa*ee-bb*dd)/den
    if not (0.001 < s < 0.999 and 0.001 < t < 0.999):
        return None
    x, y = add(a, mul(ab, s)), add(c, mul(cd, t))
    difference = sub(x, y)
    distance = math.sqrt(dot(difference, difference))
    if distance > 1e-6:
        normal = mul(difference, 1./distance)
    else:
        raw = cross(ab, cd)
        normal = mul(raw, 1./math.sqrt(dot(raw, raw)))
    return s, t, normal, distance


def one_edge_contact(points, inverse_masses, thickness=0.12,
                     compliance=1e-6, dt=1./60., lagrange=0.):
    closest = closest_interior(points)
    if closest is None:
        return tuple(points), lagrange
    s, t, normal, distance = closest
    if distance >= thickness*2:
        return tuple(points), lagrange
    weights = (1.-s, s, -(1.-t), -t)
    weighted_mass = sum(inv * weight*weight for inv, weight in zip(inverse_masses, weights))
    if weighted_mass <= 0:
        return tuple(points), lagrange
    alpha = compliance/dt**2
    delta_l = (thickness - distance - alpha*lagrange)/(weighted_mass+alpha)
    next_lambda = max(0., lagrange+delta_l)
    impulse = next_lambda - lagrange
    new_points = tuple(add(p, mul(normal, impulse*inv*w))
                       for p, inv, w in zip(points, inverse_masses, weights))
    return new_points, next_lambda


class EdgeSelfCollisionContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.helper = (ROOT / "servers/physics_xpbd_edge_collision.h").read_text(encoding="utf-8")
        cls.soft = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.cpp").read_text(encoding="utf-8")
        cls.soft_h = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.h").read_text(encoding="utf-8")
        cls.space = (ROOT / "modules/godot_physics_3d/godot_space_3d.cpp").read_text(encoding="utf-8")
        cls.space_h = (ROOT / "modules/godot_physics_3d/godot_space_3d.h").read_text(encoding="utf-8")
        cls.settings = (ROOT / "servers/physics_3d/physics_server_3d.cpp").read_text(encoding="utf-8")

    def test_crossing_edges_are_detected_without_vertex_face_overlap(self):
        points = ((-1., 0., 0.), (1., 0., 0.),
                  (0., -3., .02), (0., 3., .02))
        s, t, normal, distance = closest_interior(points)
        self.assertAlmostEqual(s, .5)
        self.assertAlmostEqual(t, .5)
        self.assertAlmostEqual(distance, .02)
        self.assertEqual(normal, (0., 0., -1.))

    def test_contact_moves_only_dynamic_edge_without_affecting_pins(self):
        points = ((-1., 0., 0.), (1., 0., 0.),
                  (0., -3., .02), (0., 3., .02))
        result, lagrange = one_edge_contact(points, (0., 0., 6., 6.))
        self.assertEqual(result[:2], points[:2])
        self.assertAlmostEqual(closest_interior(result)[3], .1198801438274, places=7)
        self.assertGreater(lagrange, 0.)

    def test_no_attraction_outside_envelope(self):
        points = ((-1., 0., 0.), (1., 0., 0.),
                  (0., -3., .5), (0., 3., .5))
        result, lagrange = one_edge_contact(points, (0., 0., 6., 6.))
        self.assertEqual(result, points)
        self.assertEqual(lagrange, 0.)

    def test_parallel_edges_and_endpoint_near_misses_are_skipped(self):
        self.assertIsNone(closest_interior(((0., 0., 0.), (1., 0., 0.),
                                            (0., .01, 0.), (1., .01, 0.))))
        self.assertIsNone(closest_interior(((0., 0., 0.), (1., 0., 0.),
                                            (2., -1., 0.), (2., 1., 0.))))
        self.assertIsNone(closest_interior(((0., 0., 0.), (0., 0., 0.),
                                            (0., 0., 0.), (0., 0., 1.))))

    def test_opt_in_setting_and_no_allocations_by_default(self):
        self.assertIn('"physics/3d/solver/soft_body_self_collision_edge_edge"', self.settings)
        self.assertIn('"physics/3d/solver/soft_body_self_collision_edge_edge"), false);', self.settings)
        self.assertIn("soft_body_self_collision_edge_edge = false;", self.space_h)
        self.assertIn("is_soft_body_self_collision_edge_edge_enabled()", self.space_h)
        self.assertIn('GLOBAL_GET("physics/3d/solver/soft_body_self_collision_edge_edge")', self.space)
        self.assertIn("if (with_edge_contacts) {", self.soft)
        self.assertIn("xpbd_self_edge_tree.clear();", self.soft)
        self.assertIn("xpbd_self_edges.reset();", self.soft)
        self.assertIn("xpbd_self_edge_contacts.reset();", self.soft)

    def test_structural_edges_bvh_and_topological_exclusion(self):
        self.assertIn("struct SelfCollisionEdge", self.soft_h)
        self.assertIn("struct SelfEdgeContact", self.soft_h)
        self.assertIn("DynamicBVH xpbd_self_edge_tree;", self.soft_h)
        self.assertIn("if (xpbd_self_neighbor_edges.has(key))", self.soft)
        self.assertIn("xpbd_self_edge_tree.insert(bounds, &edge)", self.soft)
        self.assertIn("xpbd_self_edge_tree.update(edge.leaf, edge_bounds)", self.soft)
        self.assertIn("xpbd_self_edge_tree.aabb_query(query, visit_edge);", self.soft)
        self.assertIn("other.index <= edge.index", self.soft)
        self.assertIn("xpbd_self_neighbor_edges.has(_soft_body_edge_key(edge.a, other.a))", self.soft)
        self.assertIn("xpbd_self_neighbor_edges.has(_soft_body_edge_key(edge.b, other.b))", self.soft)
        self.assertIn("uint64_t(65536)", self.soft)
        self.assertIn("hits >= per_edge_limit", self.soft)

    def test_xpbd_helper_unilateral_pins_finiteness(self):
        self.assertIn("physics_xpbd_closest_edges(", self.helper)
        self.assertIn("physics_xpbd_solve_edge_collision(", self.helper)
        self.assertIn("s <= 0.001 || s >= 0.999", self.helper)
        self.assertIn("const double next_lambda_double = MAX(0.0", self.helper)
        self.assertIn("if (!Math::is_finite(delta_lambda))", self.helper)
        self.assertIn("double(p_inv_a) * wa * wa", self.helper)
        self.assertIn("double(p_inv_d) * wd * wd", self.helper)
        self.assertIn("const Vector3 next_c = corrected(r_c, -double(p_inv_c) * wc);", self.helper)
        self.assertIn("if (!next_a.is_finite() || !next_b.is_finite()", self.helper)
        self.assertIn("r_a = next_a;\n\tr_b = next_b;\n\tr_c = next_c;\n\tr_d = next_d;", self.helper)
        self.assertIn("previous_separation.dot(normal) < 0.0", self.soft)

    def test_runtime_and_workflow_registration(self):
        case = "physics_soft_body_edge_collision_3d"
        self.assertIn(f'"{case}"', (STRESS / "run.py").read_text(encoding="utf-8"))
        self.assertIn(f'"{case}":', (STRESS / "stress.gd").read_text(encoding="utf-8"))
        workload = (STRESS / f"{case}.gd").read_text(encoding="utf-8")
        self.assertIn("var baseline: Dictionary =", workload)
        self.assertIn("var repelled: Dictionary =", workload)
        self.assertIn("repelled.min_edge_distance > 0.06", workload)
        self.assertIn("soft_body_pin_point(body, j, true)", workload)
        self.assertIn('3d/physics_engine="GodotPhysics3D"',
                      (STRESS / "project.godot").read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
