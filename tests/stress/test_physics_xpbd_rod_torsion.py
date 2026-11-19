"""Geometric rod centerline torsion contracts, independent numeric reference.

The constraint acts on FOUR POSITIONAL vertices. It is a signed dihedral
between consecutive bending planes, not Cosserat material-frame twist.
"""

import math
from pathlib import Path
import random
import unittest

ROOT = Path(__file__).resolve().parents[2]


def add(a, b):
    return tuple(x+y for x, y in zip(a, b))


def sub(a, b):
    return tuple(x-y for x, y in zip(a, b))


def mul(a, k):
    return tuple(x*k for x in a)


def dot(a, b):
    return sum(x*y for x, y in zip(a, b))


def cross(a, b):
    return (
        a[1]*b[2]-a[2]*b[1],
        a[2]*b[0]-a[0]*b[2],
        a[0]*b[1]-a[1]*b[0],
    )


def norm(a):
    return math.sqrt(dot(a, a))


def torsion(a, b, c, d):
    # Map a--b--c--d to the oriented shared dihedral (b,c,a,d).
    e = sub(c, b)
    na = cross(e, sub(a, b))
    nd = cross(sub(d, b), e)
    if norm(e) < 1e-10 or norm(na) < 1e-10 or norm(nd) < 1e-10:
        raise ValueError("straight/degenerate centerline has no bend plane")
    e = mul(e, 1/norm(e))
    na = mul(na, 1/norm(na))
    nd = mul(nd, 1/norm(nd))
    return math.atan2(dot(e, cross(na, nd)), dot(na, nd))


def solve_once(points, weights, rest_angle, alpha, lam):
    # Mirror the Godot XPBD signed-dihedral gradients with the remapping
    # of outer/inner centerline vertices: hinge=(b,c,a,d).
    a, b, c, d = points
    x = [b, c, a, d]
    w = [weights[1], weights[2], weights[0], weights[3]]
    e = sub(x[1], x[0])
    na = cross(e, sub(x[2], x[0]))
    nd = cross(sub(x[3], x[0]), e)
    e2, len_e = dot(e, e), norm(e)
    nc2, nd2 = dot(na, na), dot(nd, nd)
    if e2 < 1e-14 or nc2 < 1e-14 or nd2 < 1e-14:
        return points, lam
    gc = mul(na, -len_e/nc2)
    gd = mul(nd, -len_e/nd2)
    ga = add(
        mul(gc, dot(sub(x[2], x[1]), e)/e2),
        mul(gd, dot(sub(x[3], x[1]), e)/e2)
    )
    gb = add(
        mul(gc, dot(sub(x[0], x[2]), e)/e2),
        mul(gd, dot(sub(x[0], x[3]), e)/e2)
    )
    gradients = [ga, gb, gc, gd]
    effective_mass = sum(w[i]*dot(gradients[i], gradients[i]) for i in range(4))
    if not effective_mass:
        return points, lam
    error = torsion(a, b, c, d)-rest_angle
    if error > math.pi:
        error -= 2*math.pi
    if error < -math.pi:
        error += 2*math.pi
    delta_lambda = -(error+alpha*lam)/(effective_mass+alpha)
    updated = [add(x[i], mul(gradients[i], w[i]*delta_lambda)) for i in range(4)]
    return (updated[2], updated[0], updated[1], updated[3]), lam+delta_lambda


def select_torsions(bends, points):
    # Reconstruct continuous centerline segments using per-center
    # rod-bend triplet indexing, preserving the same real mesh strand.
    by_center = [[] for _ in points]
    for a, b, c in bends:
        by_center[b].append((a, b, c))
    result = []
    for a0, b, c0 in bends:
        for a, c in ((a0, c0), (c0, a0)):
            for a2, _, c2 in by_center[c]:
                if a2 == b:
                    d = c2
                elif c2 == b:
                    d = a2
                else:
                    continue
                if len({a, b, c, d}) != 4 or a >= d:
                    continue
                try:
                    rest = torsion(points[a], points[b], points[c], points[d])
                except ValueError:
                    continue
                result.append((a, b, c, d, rest))
    return result


class TestXPBDRodTorsion(unittest.TestCase):
    def setUp(self):
        self.p = ((-1., 0., 0.), (0., 0., 0.), (1., 1., 0.),
                  (2., 1.1, 0.5))

    def test_planar_curve_zero_and_signed_chirality(self):
        a, b, c, d = self.p
        self.assertAlmostEqual(torsion(a, b, c, (2., 1.1, 0.)), 0., delta=1e-10)
        self.assertAlmostEqual(
            torsion(a, b, c, d),
            -torsion(a, b, c, (d[0], d[1], -d[2])), delta=1e-12)

    def test_translation_and_rotation_invariance(self):
        rng = random.Random(0x79A5)
        for _ in range(1500):
            phi = rng.uniform(-math.pi, math.pi)
            co, si = math.cos(phi), math.sin(phi)
            t = tuple(rng.uniform(-50, 50) for _ in range(3))
            def transformed(x):
                return add((co*x[0]-si*x[1], si*x[0]+co*x[1], x[2]), t)
            a, b, c, d = self.p
            self.assertAlmostEqual(torsion(a, b, c, d),
                                   torsion(*map(transformed, self.p)), delta=1e-11)

    def test_rest_signed_angle_preserved(self):
        rest = torsion(*self.p)
        out, lam = solve_once(self.p, (1, 1, 1, 1), rest, 0.1, 0)
        self.assertEqual(out, self.p)
        self.assertEqual(lam, 0)

    def test_stiff_torsion_resists_spatial_twisting(self):
        def project(alpha):
            p, lam = self.p, 0.
            for _ in range(12):
                p, lam = solve_once(p, (0, 0, 0, 1), 0, alpha, lam)
            return abs(torsion(*p))
        self.assertLess(project(0.1), project(5.0))
        self.assertLess(project(5.0), abs(torsion(*self.p)))

    def test_equal_mass_translation_invariant_projection(self):
        rng = random.Random(0x2233)
        for _ in range(500):
            a, b, c, d = self.p
            d = (2., 1.1, rng.uniform(-1., 1.))
            if abs(d[2]) < 0.01:
                continue
            points = (a, b, c, d)
            old = tuple(sum(p[j] for p in points) for j in range(3))
            projected, _ = solve_once(points, (1, 1, 1, 1), 0, 0.1, 0)
            new = tuple(sum(p[j] for p in projected) for j in range(3))
            self.assertLess(norm(sub(new, old)), 1e-11)

    def test_pins_remain_fixed(self):
        projected, lam = solve_once(self.p, (1, 0, 0, 1), 0, 0.1, 0)
        self.assertEqual(projected[1], self.p[1])
        self.assertEqual(projected[2], self.p[2])
        self.assertTrue(math.isfinite(lam))

    def test_straight_centerline_cannot_encode_material_twist(self):
        with self.assertRaises(ValueError):
            torsion((-1, 0, 0), (0, 0, 0), (1, 0, 0), (2, 0, 0))

    def test_four_node_chain_continuity_and_no_duplicates(self):
        # Three overlapping bends encode two distinct four-node windows.
        bends = [(0, 1, 2), (1, 2, 3), (2, 3, 4)]
        points = [
            (-1, 0, 0), (0, 0, 0), (1, 1, 0),
            (2, 1.1, 0.5), (3, 1.3, -0.2)
        ]
        generated = select_torsions(bends, points)
        self.assertEqual(len(generated), 2)
        self.assertEqual({tuple(q[:4]) for q in generated},
                         {(0, 1, 2, 3), (1, 2, 3, 4)})

    def test_disconnected_branches_and_planar_straight_segments_rejected(self):
        bends = [(0, 1, 2), (3, 4, 5)]
        points = [(i, 0, 0) for i in range(6)]
        self.assertEqual(select_torsions(bends, points), [])

    def test_native_wiring_and_lifecycle(self):
        header = (ROOT / "servers/physics_xpbd_rod_torsion.h").read_text()
        body_h = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.h").read_text()
        body = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.cpp").read_text()
        space_h = (ROOT / "modules/godot_physics_3d/godot_space_3d.h").read_text()
        space = (ROOT / "modules/godot_physics_3d/godot_space_3d.cpp").read_text()
        server = (ROOT / "servers/physics_3d/physics_server_3d.cpp").read_text()
        prop = "physics/3d/solver/soft_body_xpbd_rod_torsion_compliance"
        self.assertIn(f'"{prop}"', server)
        self.assertIn(f'GLOBAL_GET("{prop}")', space)
        self.assertIn("soft_body_xpbd_rod_torsion_compliance = 0.0;", space_h)
        self.assertIn("struct RodTorsionConstraint", body_h)
        self.assertIn("xpbd_rod_torsions;", body_h)
        self.assertEqual(body.count("initialize_rod_torsion_constraints();"), 2)
        self.assertIn("void GodotSoftBody3D::initialize_rod_torsion_constraints()", body)
        self.assertIn("rods_by_center.resize(nodes.size());", body)
        self.assertIn("if (d == a || d == b || d == c || a >= d)", body)
        self.assertIn("physics_xpbd_rod_geometric_torsion_angle(", body)
        self.assertIn("physics_xpbd_solve_rod_geometric_torsion(", body)
        self.assertIn("torsion.lambda = real_t(0.0);", body)
        self.assertIn("xpbd_rod_torsions.reset();", body[body.index("void GodotSoftBody3D::destroy()"):])
        self.assertIn("physics_xpbd_solve_dihedral(r_b, r_c, r_a, r_d", header)
        self.assertIn("get_soft_body_xpbd_rod_torsion_compliance() <= 0.0)", body)

if __name__ == "__main__":
    unittest.main()
