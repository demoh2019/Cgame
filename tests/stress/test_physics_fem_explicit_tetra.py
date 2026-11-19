"""Reference and integration contracts for imported concave tetrahedral FEM.

Run:
  python3 -m unittest discover -s tests/stress -p 'test_physics_fem_explicit_tetra.py' -v

The reference validates directed surface faces, pairwise internal faces,
positive tet volumes and the aggregate enclosed volume. It does not claim
to detect every geometric self-intersection of arbitrary imported tets.
"""
import math
from pathlib import Path
import random
import unittest

ROOT = Path(__file__).resolve().parents[2]
POINTS = ((0, 0, 0), (1, 0, 0), (0, 1, 0), (0, 0, 1), (.6, .8, -.25))
SHELL = ((1, 2, 3), (0, 3, 2), (0, 1, 3),
         (2, 1, 4), (0, 4, 1), (0, 2, 4))
TETS = ((0, 1, 2, 3), (0, 2, 1, 4))


def diff(a, b):
    return tuple(x - y for x, y in zip(a, b))


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1],
            a[2] * b[0] - a[0] * b[2],
            a[0] * b[1] - a[1] * b[0])


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def det(p, tet):
    a, b, c, d = (p[i] for i in tet)
    return dot(diff(b, a), cross(diff(c, a), diff(d, a)))


def shell_volume(p, faces):
    origin = p[0]
    return sum(dot(diff(p[a], origin),
                   cross(diff(p[b], origin), diff(p[c], origin)))
               for a, b, c in faces) / 6


def oriented(triangle):
    a, b, c = triangle
    parity = (a > b) ^ (a > c) ^ (b > c)
    return tuple(sorted(triangle)), parity


def cook(points, faces, tets, signed_volume):
    if (not 4 <= len(points) <= 2048 or
            not 4 <= len(faces) <= 4096 or
            not 1 <= len(tets) <= 4096 or
            not math.isfinite(signed_volume) or signed_volume == 0):
        return None
    if any(not all(math.isfinite(x) for x in p) for p in points):
        return None
    surface = {}
    for face in faces:
        if len(face) != 3 or len(set(face)) != 3 or any(
                i < 0 or i >= len(points) for i in face):
            return None
        key, parity = oriented(face)
        if key in surface:
            return None
        surface[key] = parity ^ (signed_volume < 0)
    all_faces = {}
    used = set()
    total = 0.0
    cooked = []
    for tet in tets:
        if len(tet) != 4 or len(set(tet)) != 4 or any(
                i < 0 or i >= len(points) for i in tet):
            return None
        tet = list(tet)
        signed = det(points, tet)
        scale = math.prod(
            math.sqrt(dot(diff(points[i], points[tet[0]]),
                          diff(points[i], points[tet[0]])))
            for i in tet[1:])
        if (not math.isfinite(signed) or
                not math.isfinite(scale) or
                not scale > 0 or not abs(signed) > scale * 1e-8):
            return None
        if signed < 0:
            tet[1], tet[2] = tet[2], tet[1]
            signed = -signed
        total += signed / 6
        a, b, c, d = tet
        for face in ((b, c, d), (a, d, c), (a, b, d), (a, c, b)):
            key, parity = oriented(face)
            all_faces.setdefault(key, []).append((parity, len(cooked)))
        used.update(tet)
        cooked.append(tuple(tet))
    if len(used) != len(points) or abs(total - abs(signed_volume)) > abs(signed_volume) * 1e-5:
        return None
    boundary = {}
    for key, records in all_faces.items():
        if len(records) == 1:
            boundary[key] = records[0][0]
        elif len(records) != 2 or records[0][0] == records[1][0] or records[0][1] == records[1][1]:
            return None
    if boundary != surface:
        return None
    return cooked


class ExplicitTetraContracts(unittest.TestCase):
    def test_nonconvex_two_tet_assembly(self):
        self.assertAlmostEqual(shell_volume(POINTS, SHELL), 1.25 / 6)
        self.assertEqual(cook(POINTS, SHELL, TETS, 1.25 / 6), list(TETS))

    def test_auto_orient_negative_input_winding(self):
        bad = ((0, 2, 1, 3), TETS[1])
        cooked = cook(POINTS, SHELL, bad, 1.25 / 6)
        self.assertEqual(cooked, list(TETS))

    def test_reversed_surface_is_supported(self):
        inward = tuple((a, c, b) for a, b, c in SHELL)
        self.assertEqual(cook(POINTS, inward, TETS, -1.25 / 6), list(TETS))

    def test_bad_boundary_and_invalid_indices(self):
        self.assertIsNone(cook(POINTS, SHELL[:-1], TETS, 1.25 / 6))
        self.assertIsNone(cook(POINTS, SHELL, TETS[:-1], 1.25 / 6))
        self.assertIsNone(cook(POINTS, SHELL, TETS + (TETS[0],), .375))
        self.assertIsNone(cook(POINTS, SHELL, ((0, 1, 2, 0), TETS[1]), 1.25 / 6))
        self.assertIsNone(cook(POINTS, SHELL, ((0, 1, 2, 9), TETS[1]), 1.25 / 6))
        reversed_face = list(SHELL)
        a, b, c = reversed_face[0]
        reversed_face[0] = (a, c, b)
        self.assertIsNone(cook(POINTS, reversed_face, TETS, 1.25 / 6))

    def test_random_2500_rigid_transforms_and_scales(self):
        rng = random.Random(20261119)
        for _ in range(2500):
            u = [rng.uniform(-1, 1) for _ in range(3)]
            length = math.sqrt(dot(u, u))
            u = [v / length for v in u]
            theta = rng.uniform(-math.pi, math.pi)
            sn, cs = math.sin(theta), math.cos(theta)
            offset = [rng.uniform(-5, 5) for _ in range(3)]
            scale = 10 ** rng.uniform(-5, 8)

            def transform(p):
                cross_u = cross(u, p)
                v = dot(u, p)
                return tuple(scale * (cs * p[i] + sn * cross_u[i] +
                                     (1 - cs) * u[i] * v + offset[i])
                             for i in range(3))

            rotated = tuple(transform(p) for p in POINTS)
            volume = shell_volume(rotated, SHELL)
            cooked = cook(rotated, SHELL, TETS, volume)
            self.assertEqual(cooked, list(TETS))
            self.assertAlmostEqual(
                sum(abs(det(rotated, t)) / 6 for t in cooked) / volume,
                1.0, delta=1e-7)

    def test_unchanged_automatic_convex_path_when_no_indices(self):
        body = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.cpp").read_text()
        self.assertIn('if (!xpbd_explicit_tetra_visual_indices.is_empty())', body)
        self.assertIn('physics_fem_build_explicit_tetrahedra(', body)
        self.assertIn('physics_fem_build_convex_star_tetrahedra(', body)
        self.assertIn('tet_indices.push_back(welded);', body)

    def test_scene_server_and_backend_all_wired(self):
        server = (ROOT / "servers/physics_3d/physics_server_3d.h").read_text()
        backend = (ROOT / "modules/godot_physics_3d/godot_physics_server_3d.cpp").read_text()
        scene = (ROOT / "scene/3d/physics/soft_body_3d.cpp").read_text()
        lab = (ROOT / "demo/physics_lab/lab_3d.gd").read_text()
        self.assertIn("virtual void soft_body_set_tetrahedral_indices", server)
        self.assertIn("soft_body->set_tetrahedral_indices(p_indices);", backend)
        self.assertIn("SoftBody3D::set_tetrahedral_indices", scene)
        self.assertIn('Variant::PACKED_INT32_ARRAY, "tetrahedral_indices"', scene)
        self.assertIn("FEMConcaveImportedTwoTets", lab)
        self.assertIn("PackedInt32Array([0, 1, 2, 3, 0, 2, 1, 4])", lab)

    def test_zero_runtime_buffers_by_default(self):
        header = (ROOT / "servers/physics_fem_explicit_tetra.h").read_text()
        body = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.cpp").read_text()
        self.assertIn("r_tetrahedra = std::move(cooked);", header)
        self.assertIn("p_indices.size() / 4 > 4096", header)
        self.assertIn("tet_faces.push_back(", header)
        self.assertIn("first.odd == second.odd", header)
        self.assertIn("if (!xpbd_explicit_tetra_visual_indices.is_empty())", body)


CUBE_INTERIOR_POINTS = (
    (-1, -1, -1), (1, -1, -1), (1, 1, -1), (-1, 1, -1),
    (-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1),
    (0, 0, 0),
)
CUBE_FACES = (
    (0, 2, 1), (0, 3, 2),
    (4, 5, 6), (4, 6, 7),
    (0, 1, 5), (0, 5, 4),
    (3, 7, 6), (3, 6, 2),
    (0, 4, 7), (0, 7, 3),
    (1, 2, 6), (1, 6, 5),
)
CUBE_INTERIOR_TETS = tuple((8, *face) for face in CUBE_FACES)


class InteriorFEMContracts(unittest.TestCase):
    def test_cube_cooks_twelve_elements_with_one_interior_vertex(self):
        self.assertEqual(shell_volume(CUBE_INTERIOR_POINTS, CUBE_FACES), 8)
        cooked = cook(CUBE_INTERIOR_POINTS, CUBE_FACES, CUBE_INTERIOR_TETS, 8)
        self.assertEqual(cooked, list(CUBE_INTERIOR_TETS))
        self.assertEqual(len(cooked), 12)
        self.assertAlmostEqual(
            sum(abs(det(CUBE_INTERIOR_POINTS, tet)) / 6 for tet in cooked), 8)

    def test_outside_or_degenerate_interior_nodes_are_rejected(self):
        points = list(CUBE_INTERIOR_POINTS)
        points[8] = (3, 3, 3)
        self.assertIsNone(cook(points, CUBE_FACES, CUBE_INTERIOR_TETS, 8))
        points[8] = points[0]
        self.assertIsNone(cook(points, CUBE_FACES, CUBE_INTERIOR_TETS, 8))

    def test_random_4000_interior_node_rigid_transforms(self):
        rng = random.Random(20261119)
        for _ in range(4000):
            axis = [rng.uniform(-1, 1) for _ in range(3)]
            length = math.sqrt(dot(axis, axis))
            axis = [x / length for x in axis]
            theta = rng.uniform(-math.pi, math.pi)
            cs, sn = math.cos(theta), math.sin(theta)
            scale = 10 ** rng.uniform(-5, 8)
            offset = [rng.uniform(-4, 4) * scale for _ in range(3)]

            def move(p):
                twist = cross(axis, p)
                along = dot(axis, p)
                return tuple(
                    scale * (cs * p[i] + sn * twist[i] +
                             (1 - cs) * axis[i] * along) + offset[i]
                    for i in range(3)
                )

            points = tuple(move(p) for p in CUBE_INTERIOR_POINTS)
            volume = shell_volume(points, CUBE_FACES)
            tets = cook(points, CUBE_FACES, CUBE_INTERIOR_TETS, volume)
            self.assertEqual(tets, list(CUBE_INTERIOR_TETS))
            self.assertAlmostEqual(
                sum(abs(det(points, t)) / 6 for t in tets) / volume,
                1.0, delta=1e-7)

    def test_scene_interior_api_and_collisions_exclusion(self):
        scene = (ROOT / "scene/3d/physics/soft_body_3d.cpp").read_text()
        server = (ROOT / "servers/physics_3d/physics_server_3d.cpp").read_text()
        body = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.cpp").read_text()
        header = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.h").read_text()
        demo = (ROOT / "demo/physics_lab/lab_3d.gd").read_text()
        self.assertIn('Variant::PACKED_VECTOR3_ARRAY, "tetrahedral_interior_positions"', scene)
        self.assertIn('D_METHOD("soft_body_set_tetrahedral_interior_positions"', server)
        self.assertIn("set_tetrahedral_interior_positions", body)
        self.assertIn("xpbd_surface_node_count = node_count;", body)
        self.assertIn("xpbd_surface_node_count + uint32_t(internal_index)", body)
        self.assertIn("if (i < xpbd_surface_node_count)", body)
        self.assertIn("if (node.index >= xpbd_surface_node_count)", body)
        self.assertIn("node_id < xpbd_surface_node_count", body)
        self.assertIn("p_vertices.xpbd_surface_node_count", body)
        self.assertIn("uint32_t xpbd_surface_node_count = 0;", header)
        self.assertIn("FEMInteriorNodeTwelveTets", demo)

    def test_interior_invalid_geometry_is_not_allocated(self):
        body = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.cpp").read_text()
        start = body.index("bool GodotSoftBody3D::create_from_trimesh(")
        finish = body.index("void GodotSoftBody3D::generate_bending_constraints(", start)
        creation = body[start:finish]
        self.assertIn("physics_fem_build_explicit_tetrahedra(", creation)
        self.assertIn("vertices.resize(xpbd_surface_node_count);", creation)
        self.assertLess(
            creation.index("physics_fem_build_explicit_tetrahedra("),
            creation.index("nodes.resize(node_count);"))
        self.assertIn("if (valid_indices && physics_fem_build_explicit_tetrahedra(", creation)

    def test_runtime_fem_diagnostics_are_exposed_and_asserted(self):
        header = (ROOT / "servers/physics_3d/physics_server_3d.h").read_text()
        backend = (ROOT / "modules/godot_physics_3d/godot_physics_server_3d.cpp").read_text()
        smoke = (ROOT / "demo/physics_lab/smoke_test.gd").read_text()
        self.assertIn("soft_body_get_tetrahedron_count", header)
        self.assertIn("soft_body_get_tetrahedral_interior_node_count", header)
        self.assertIn("get_fem_tetrahedron_count()", backend)
        self.assertIn("get_fem_interior_node_count()", backend)
        self.assertIn('"FEMConvexCubeSixTets": [6, 0]', smoke)
        self.assertIn('"FEMConcaveImportedTwoTets": [2, 0]', smoke)
        self.assertIn('"FEMInteriorNodeTwelveTets": [12, 1]', smoke)

    def test_disabled_fem_preserves_surface_mass_and_freezes_internal_particles(self):
        body = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.cpp").read_text()
        self.assertIn("if (xpbd_fem_tetrahedra.is_empty() &&", body)
        self.assertIn("const real_t surface_inverse = real_t(xpbd_surface_node_count) * inv_total_mass;", body)
        self.assertIn("for (uint32_t i = xpbd_surface_node_count; i < nodes.size(); ++i)", body)
        self.assertIn("node.im = 0.0;", body)
        self.assertIn("++dynamic_node_count;", body)
        self.assertIn("--dynamic_node_count;", body)
        self.assertIn("if (!xpbd_fem_tetrahedra.is_empty()) {", body)

    def test_no_surface_change_for_default_empty_interior_positions(self):
        body = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.cpp").read_text()
        self.assertIn("if (extra_count > 0)", body)
        self.assertIn("if (i < xpbd_surface_node_count)", body)
        self.assertIn("xpbd_surface_node_count = 0;", body)


if __name__ == "__main__":
    unittest.main()
