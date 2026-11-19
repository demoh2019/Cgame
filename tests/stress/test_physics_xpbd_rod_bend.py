"""Independent XPBD three-point discrete-rod bending contracts.

The native implementation constrains the bend angle of a centerline triplet
selected from nearly opposite original triangle edges. This is NOT a full
Cosserat rod with independent material-frame rotations or twist.
"""

import math
from pathlib import Path
import random
import unittest

ROOT = Path(__file__).resolve().parents[2]


def minus(a, b):
    return tuple(x-y for x, y in zip(a, b))


def plus(a, b):
    return tuple(x+y for x, y in zip(a, b))


def scale(a, x):
    return tuple(v*x for v in a)


def dot(a, b):
    return sum(x*y for x, y in zip(a, b))


def cross(a, b):
    return (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0])


def norm(a):
    return math.sqrt(dot(a, a))


def rod_angle(a, b, c):
    u = minus(a, b)
    v = minus(c, b)
    ul, vl = norm(u), norm(v)
    if not (ul > 1e-12 and vl > 1e-12):
        raise ValueError("degenerate rod")
    nu, nv = scale(u, 1/ul), scale(v, 1/vl)
    cosine = min(1.0, max(-1.0, dot(nu, nv)))
    return math.atan2(norm(cross(nu, nv)), -cosine)


def rod_projection(a, b, c, wa, wb, wc, rest, alpha, lam):
    angle = rod_angle(a, b, c)
    err = angle-rest
    if abs(err) < 1e-12 and lam == 0:
        return a, b, c, lam
    u, v = minus(a, b), minus(c, b)
    ul, vl = norm(u), norm(v)
    nu, nv = scale(u, 1/ul), scale(v, 1/vl)
    cosine = min(1.0, max(-1.0, dot(nu, nv)))
    sine = norm(cross(nu, nv))
    if sine <= 1e-9:
        return a, b, c, lam
    ga = scale(minus(nv, scale(nu, cosine)), 1/(ul*sine))
    gc = scale(minus(nu, scale(nv, cosine)), 1/(vl*sine))
    gb = scale(plus(ga, gc), -1)
    mass = wa*dot(ga, ga)+wb*dot(gb, gb)+wc*dot(gc, gc)
    if mass <= 0:
        return a, b, c, lam
    dlam = -(err+alpha*lam)/(mass+alpha)
    return (
        plus(a, scale(ga, wa*dlam)),
        plus(b, scale(gb, wb*dlam)),
        plus(c, scale(gc, wc*dlam)),
        lam+dlam
    )


def solve(a, b, c, weights, rest, compliance, iterations=12):
    lam = 0.0
    for _ in range(iterations):
        a, b, c, lam = rod_projection(
            a, b, c, weights[0], weights[1], weights[2], rest, compliance, lam
        )
    return a, b, c, lam


def select_rod_triplets(positions, triangles, straightness=0.9):
    # Build from ORIGINAL face edges, not synthetic bending links.
    neighbors = [set() for _ in positions]
    for a, b, c in triangles:
        for x, y in ((a, b), (b, c), (c, a)):
            neighbors[x].add(y)
            neighbors[y].add(x)
    out = []
    for middle, adjacent_set in enumerate(neighbors):
        adjacent = sorted(adjacent_set)
        used = set()
        for _ in range(2):
            best_score = straightness
            choice = None
            for i in range(len(adjacent)):
                if adjacent[i] in used:
                    continue
                for j in range(i+1, len(adjacent)):
                    if adjacent[j] in used:
                        continue
                    u = minus(positions[adjacent[i]], positions[middle])
                    v = minus(positions[adjacent[j]], positions[middle])
                    if norm(u) < 1e-12 or norm(v) < 1e-12:
                        continue
                    alignment = -dot(u, v)/norm(u)/norm(v)
                    if alignment > best_score:
                        best_score, choice = alignment, (adjacent[i], adjacent[j])
            if choice is None:
                break
            a, c = choice
            used.add(a)
            used.add(c)
            out.append((a, middle, c, rod_angle(positions[a], positions[middle], positions[c])))
    return out


class TestXPBDDiscreteRodBending(unittest.TestCase):
    def test_straight_and_curved_angles(self):
        self.assertAlmostEqual(rod_angle((-1, 0, 0), (0, 0, 0), (1, 0, 0)), 0)
        self.assertAlmostEqual(rod_angle((-1, 0, 0), (0, 0, 0), (1, 1, 0)), math.pi/4)
        self.assertAlmostEqual(rod_angle((-1, 0, 0), (0, 0, 0), (-1, 0, 0)), math.pi)

    def test_stiffness_and_pins(self):
        a, b, c = (-1, 0, 0), (0, 0, 0), (1, 0.4, 0)
        stiff = solve(a, b, c, (0, 0, 1), 0, 0.1)
        soft = solve(a, b, c, (0, 0, 1), 0, 5.0)
        self.assertEqual(stiff[:2], (a, b))
        self.assertLess(rod_angle(*stiff[:3]), rod_angle(*soft[:3]))
        self.assertLess(rod_angle(*soft[:3]), rod_angle(a, b, c))

    def test_precurved_rest_shape_is_preserved(self):
        a, b, c = (-1, 0, 0), (0, 0, 0), (1, 0.35, 0)
        result = solve(a, b, c, (1, 1, 1), rod_angle(a, b, c), 0.1)
        self.assertEqual(result, (a, b, c, 0.0))

    def test_angular_projection_gradient_matches_finite_difference(self):
        rng = random.Random(0xCC03)
        h = 1e-6
        for _ in range(200):
            a = (-1, rng.uniform(-0.2, 0.2), rng.uniform(-0.2, 0.2))
            b = (0, 0, 0)
            c = (1, rng.uniform(0.2, 1.2), rng.uniform(-0.2, 0.2))
            u, v = minus(a, b), minus(c, b)
            nu, nv = scale(u, 1/norm(u)), scale(v, 1/norm(v))
            cosine = dot(nu, nv)
            sine = norm(cross(nu, nv))
            analytic = scale(minus(nv, scale(nu, cosine)), 1/(norm(u)*sine))
            for axis in range(3):
                offset = tuple(h if axis == j else 0 for j in range(3))
                numerical = (
                    rod_angle(plus(a, offset), b, c) -
                    rod_angle(minus(a, offset), b, c)
                ) / (2*h)
                self.assertAlmostEqual(analytic[axis], numerical, delta=1e-5)

    def test_rigid_frame_invariance(self):
        rng = random.Random(0xB014)
        for _ in range(1500):
            a, b, c = (
                (rng.uniform(-3, 3), rng.uniform(-3, 3), rng.uniform(-3, 3))
                for _ in range(3)
            )
            before = rod_angle(a, b, c)
            theta = rng.uniform(-math.pi, math.pi)
            cos, sin = math.cos(theta), math.sin(theta)
            translation = (rng.uniform(-20, 20), rng.uniform(-20, 20), rng.uniform(-20, 20))
            def transform(p):
                return plus((cos*p[0]-sin*p[1], sin*p[0]+cos*p[1], p[2]), translation)
            after = rod_angle(transform(a), transform(b), transform(c))
            self.assertAlmostEqual(before, after, delta=1e-11)

    def test_equal_mass_momentum_preserved(self):
        rng = random.Random(0xCA8E)
        for _ in range(1000):
            a, b, c = (-1, 0, 0), (0, 0, 0), (1, rng.uniform(0.01, 1.0), rng.uniform(-0.5, 0.5))
            center = plus(plus(a, b), c)
            a2, b2, c2, _ = rod_projection(a, b, c, 1, 1, 1, 0, 0.1, 0)
            moved = plus(plus(a2, b2), c2)
            self.assertLess(norm(minus(moved, center)), 1e-11)

    def test_original_triangle_topology_yields_distinct_straight_chains(self):
        grid = [(float(x), 0.0, float(y)) for y in range(3) for x in range(3)]
        triangles = []
        for y in range(2):
            for x in range(2):
                a, b, c, d = y*3+x, y*3+x+1, (y+1)*3+x, (y+1)*3+x+1
                triangles.extend(((a, b, c), (b, d, c)))
        constraints = select_rod_triplets(grid, triangles)
        at_center = [quad for quad in constraints if quad[1] == 4]
        self.assertEqual(len(at_center), 2)
        self.assertEqual({frozenset((q[0], q[2])) for q in at_center},
                         {frozenset((3, 5)), frozenset((1, 7))})

    def test_does_not_construct_rods_from_missing_or_open_edges(self):
        grid = [(-1, 0, 0), (0, 0, 0), (1, 0, 0)]
        self.assertEqual(select_rod_triplets(grid, []), [])
        self.assertEqual(select_rod_triplets(grid, [(0, 1, 1)]), [])

    def test_source_wiring_and_default_disabled(self):
        settings = (ROOT / "servers/physics_3d/physics_server_3d.cpp").read_text()
        space_h = (ROOT / "modules/godot_physics_3d/godot_space_3d.h").read_text()
        space = (ROOT / "modules/godot_physics_3d/godot_space_3d.cpp").read_text()
        body_h = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.h").read_text()
        body = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.cpp").read_text()
        kernel = (ROOT / "servers/physics_xpbd_rod_bend.h").read_text()
        name = "soft_body_xpbd_rod_bend_compliance"
        self.assertIn(f'"physics/3d/solver/{name}"', settings)
        self.assertIn(f'GLOBAL_GET("physics/3d/solver/{name}")', space)
        self.assertIn(f"{name} = 0.0;", space_h)
        self.assertIn("soft_body_xpbd_rod_straightness = 0.9;", space_h)
        self.assertIn("LocalVector<RodBendConstraint> xpbd_rod_bends;", body_h)
        self.assertIn("initialize_rod_bend_constraints();", body)
        self.assertIn("physics_xpbd_rod_bend_angle(", body)
        self.assertIn("physics_xpbd_solve_rod_bend(", body)
        self.assertIn("xpbd_rod_bends.reset();", body)
        self.assertIn("if (use_rod_bend_xpbd)", body)
        self.assertIn("physics_xpbd_solve_rod_bend(", kernel)
        self.assertIn("for (const Face &face : faces)", body[
            body.index("void GodotSoftBody3D::initialize_rod_bend_constraints()"):
            body.index("// Build one-ring adjacency from ORIGINAL triangle edges.")
        ])
        # No extra setup traversal or solver call when the setting is zero.
        self.assertIn("get_space()->get_soft_body_xpbd_rod_bend_compliance() <= 0.0", body)
        destroy = body.index("void GodotSoftBody3D::destroy()")
        self.assertIn("xpbd_rod_bends.reset();", body[destroy:])


if __name__ == "__main__":
    unittest.main()
