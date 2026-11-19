"""Reference and integration contracts for convex closed-shell multi-tet FEM.

The engine uses a conservative convex surface fan. This reference checks
geometric coverage under translation, rotation, scale and reversed winding,
plus rejection of nonconvex and incorrectly oriented geometry.

Run: python3 -m unittest discover -s tests/stress -p test_physics_fem_convex_star.py -v

This does not replace native C++ compilation or a Godot runtime smoke test.
"""

import math
from pathlib import Path
import random
import unittest

ROOT = Path(__file__).resolve().parents[2]
CUBE = (
    (0, 0, 0), (1, 0, 0), (1, 1, 0), (0, 1, 0),
    (0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1),
)
FACES = (
    (0, 2, 1), (0, 3, 2),
    (4, 5, 6), (4, 6, 7),
    (0, 1, 5), (0, 5, 4),
    (3, 7, 6), (3, 6, 2),
    (0, 4, 7), (0, 7, 3),
    (1, 2, 6), (1, 6, 5),
)


def minus(a, b):
    return [x - y for x, y in zip(a, b)]


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1],
            a[2] * b[0] - a[0] * b[2],
            a[0] * b[1] - a[1] * b[0])


def determinant(a, b, c, origin):
    u, v, w = minus(a, origin), minus(b, origin), minus(c, origin)
    return dot(u, cross(v, w))


def signed_volume(vertices, faces):
    origin = vertices[0]
    return sum(determinant(vertices[a], vertices[b], vertices[c], origin)
               for a, b, c in faces) / 6.0


def cook(vertices, faces, volume):
    if not (4 <= len(vertices) <= 2048 and 4 <= len(faces) <= 4096):
        return None
    if not math.isfinite(volume) or volume == 0:
        return None
    # Mirror the C++ deterministic sorted undirected-edge topology check.
    edges = {}
    for a, b, c in faces:
        if len({a, b, c}) != 3 or not all(0 <= i < len(vertices) for i in (a, b, c)):
            return None
        for u, v in ((a, b), (b, c), (c, a)):
            key = (min(u, v), max(u, v))
            edges.setdefault(key, []).append(1 if u < v else 2)
    if any(sorted(directions) != [1, 2] for directions in edges.values()):
        return None
    origin = vertices[0]
    extent = max(abs(v - o) for p in vertices for v, o in zip(p, origin))
    if not extent:
        return None
    orientation = 1 if volume > 0 else -1
    tolerance = extent * 1e-8
    for a, b, c in faces:
        if len({a, b, c}) != 3 or not all(0 <= i < len(vertices) for i in (a, b, c)):
            return None
        u = minus(vertices[b], vertices[a])
        v = minus(vertices[c], vertices[a])
        n = cross(u, v)
        normsq = dot(n, n)
        if not (normsq > dot(u, u) * dot(v, v) * 1e-16):
            return None
        limit = math.sqrt(normsq) * tolerance
        if any(dot(n, minus(p, vertices[a])) * orientation > limit for p in vertices):
            return None
    cooked = []
    total = 0
    for a, b, c in faces:
        if 0 in (a, b, c):
            continue
        det = determinant(vertices[a], vertices[b], vertices[c], origin)
        u, v, w = (minus(vertices[i], origin) for i in (a, b, c))
        relative = math.sqrt(dot(u, u) * dot(v, v) * dot(w, w))
        if abs(det) <= relative * 1e-8:
            if not (relative > 0) or abs(det) > relative * 1e-10:
                return None
            continue
        if det * orientation <= 0:
            return None
        cooked.append((0, a, b, c, abs(det) / 6.0))
        total += abs(det) / 6.0
    if not cooked or abs(total - abs(volume)) > abs(volume) * 1e-5:
        return None
    return cooked


class ConvexStarContracts(unittest.TestCase):
    def test_cube_fans_into_six_tetrahedra_exact_volume(self):
        volume = signed_volume(CUBE, FACES)
        self.assertEqual(volume, 1.0)
        cooked = cook(CUBE, FACES, volume)
        self.assertIsNotNone(cooked)
        self.assertEqual(len(cooked), 6)
        self.assertAlmostEqual(sum(tet[4] for tet in cooked), 1.0)

    def test_single_tetra_regression(self):
        points = ((0, 0, 0), (1, 0, 0), (0, 1, 0), (0, 0, 1))
        faces = ((1, 2, 3), (0, 3, 2), (0, 1, 3), (0, 2, 1))
        cooked = cook(points, faces, 1 / 6)
        self.assertIsNotNone(cooked)
        self.assertEqual(len(cooked), 1)

    def test_reversed_winding(self):
        reverse = tuple((a, c, b) for a, b, c in FACES)
        self.assertEqual(signed_volume(CUBE, reverse), -1)
        cooked = cook(CUBE, reverse, -1)
        self.assertIsNotNone(cooked)
        self.assertEqual(len(cooked), 6)

    def test_bounded_randomized_rigid_transforms_and_scales(self):
        rng = random.Random(20261119)
        for _ in range(4000):
            scale = 10 ** rng.uniform(-9, 20)
            # Proper rotation from a unit axis and angle.
            axis = [rng.uniform(-1, 1) for _ in range(3)]
            length = math.sqrt(dot(axis, axis))
            axis = [x / length for x in axis]
            angle = rng.uniform(-math.pi, math.pi)
            co, si = math.cos(angle), math.sin(angle)
            center = [rng.uniform(-20, 20) * scale for _ in range(3)]
            def rotate(p):
                return tuple(
                    (co * p[i] +
                     (1 - co) * dot(axis, p) * axis[i] +
                     si * cross(axis, p)[i]) * scale + center[i]
                    for i in range(3)
                )
            vertices = tuple(rotate(v) for v in CUBE)
            vol = signed_volume(vertices, FACES)
            cooked = cook(vertices, FACES, vol)
            self.assertIsNotNone(cooked)
            self.assertEqual(len(cooked), 6)
            self.assertAlmostEqual(sum(t[4] for t in cooked) / abs(vol), 1.0, delta=1e-5)

    def test_concave_vertex_and_wrong_volume_rejected(self):
        cube = list(CUBE)
        cube[6] = (0.35, 0.35, 0.35)
        self.assertIsNone(cook(cube, FACES, signed_volume(cube, FACES)))
        self.assertIsNone(cook(CUBE, FACES, .5))
        self.assertIsNone(cook(CUBE, FACES, 0))

    def test_open_and_nonmanifold_surface_rejected(self):
        self.assertIsNone(cook(CUBE, FACES[:-1], 1.0))
        self.assertIsNone(cook(CUBE, FACES + (FACES[0],), 1.0))
        bad_winding = list(FACES)
        a, b, c = bad_winding[0]
        bad_winding[0] = (a, c, b)
        self.assertIsNone(cook(CUBE, bad_winding, 1.0))

    def test_bad_topology_is_rejected_by_engine_precondition(self):
        body = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.cpp").read_text()
        self.assertIn("!xpbd_volume_closed", body)
        self.assertIn("initialize_volume_constraint();", body)
        self.assertLess(body.index("initialize_volume_constraint();"),
                        body.index("initialize_fem_tetra();"))

    def test_bounding_complexity_and_atomicity(self):
        header = (ROOT / "servers/physics_fem_convex_star.h").read_text()
        self.assertIn("p_positions.size() > 2048", header)
        self.assertIn("p_faces.size() > 4096", header)
        self.assertIn("r_tetrahedra = std::move(cooked);", header)
        self.assertIn("return false;", header)

    def test_source_caches_tets_with_per_constraint_multipliers(self):
        body = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.cpp").read_text()
        header = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.h").read_text()
        self.assertIn("physics_fem_build_convex_star_tetrahedra(", body)
        self.assertIn("for (PhysicsFEMConvexTetra &tetra : xpbd_fem_tetrahedra)", body)
        self.assertIn("tetra.lambda = 0.0;", body)
        self.assertIn("tetra.rest, fem_poisson, fem_alpha, tetra.lambda", body)
        self.assertIn("xpbd_fem_tetrahedra.reset();", body)
        self.assertIn("LocalVector<PhysicsFEMConvexTetra> xpbd_fem_tetrahedra;", header)


if __name__ == "__main__":
    unittest.main()
