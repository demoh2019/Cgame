"""Independent hydrostatic SoftBody3D pressure reference and source contracts.

This tests physical invariants of clipped linear-triangle pressure loading,
but is NOT a replacement for native C++ doctests or a Cgame simulation run.
"""

import math
from pathlib import Path
import random
import unittest

ROOT = Path(__file__).resolve().parents[2]


def hydrostatic_triangle(vertices, surface_y, pressure_gradient, orientation=1):
    """Return P1 nodal forces for one clipped triangle in world coordinates."""
    poly = []
    source = [
        (tuple(float(x) for x in vertices[i]),
         tuple(float(i == j) for j in range(3)))
        for i in range(3)
    ]
    for i in range(3):
        (a, a_weights) = source[i]
        (b, b_weights) = source[(i + 1) % 3]
        da = surface_y - a[1]
        db = surface_y - b[1]
        if (da >= 0) != (db >= 0):
            t = max(0, min(1, da / (da - db)))
            p = tuple(a[j] + (b[j] - a[j]) * t for j in range(3))
            w = tuple(a_weights[j] + (b_weights[j] - a_weights[j]) * t
                      for j in range(3))
            poly.append((p, w))
        if db >= 0:
            poly.append((b, b_weights))

    out = [[0.0, 0.0, 0.0] for _ in range(3)]
    for i in range(1, len(poly) - 1):
        tri = (poly[0], poly[i], poly[i + 1])
        a, b, c = [v[0] for v in tri]
        ux, uy, uz = [b[j] - a[j] for j in range(3)]
        vx, vy, vz = [c[j] - a[j] for j in range(3)]
        cross = [uy*vz-uz*vy, uz*vx-ux*vz, ux*vy-uy*vx]
        d = [max(0, surface_y - v[0][1]) for v in tri]
        for node in range(3):
            weight = sum(tri[j][1][node] * (sum(d) + d[j]) for j in range(3))
            for axis in range(3):
                out[node][axis] += -orientation * pressure_gradient * cross[axis] * weight / 24
    return tuple(tuple(values) for values in out)


def net_force(triangle, surface_y, pressure_gradient, orientation=1):
    f = hydrostatic_triangle(triangle, surface_y, pressure_gradient, orientation)
    return tuple(sum(v[j] for v in f) for j in range(3))


TETRA = [(0, 0, 0), (1, 0, 0), (0, 1, 0), (0, 0, 1)]
A, B, C, D = TETRA
TETRA_FACES = [(A, C, B), (A, B, D), (A, D, C), (B, C, D)]


def tetra_buoyancy(height, grad=6):
    forces = [net_force(face, height, grad) for face in TETRA_FACES]
    return tuple(sum(f[j] for f in forces) for j in range(3))


class TestSoftBodyHydrostatic(unittest.TestCase):
    def test_full_immersion_archimedes(self):
        for surface in (1.0, 2.0, 20.0):
            x, y, z = tetra_buoyancy(surface, 6)
            self.assertAlmostEqual(x, 0, places=12)
            self.assertAlmostEqual(z, 0, places=12)
            self.assertAlmostEqual(y, 1.0, places=12)

    def test_partial_tetrahedron_analytic_displaced_volume(self):
        for level in (0.0, 0.05, 0.1, 0.25, 0.5, 0.75, 0.95, 1.0):
            x, y, z = tetra_buoyancy(level, 6)
            expected = 1.0 - (1.0 - level) ** 3
            self.assertAlmostEqual(x, 0.0, delta=1e-12)
            self.assertAlmostEqual(y, expected, delta=1e-12)
            self.assertAlmostEqual(z, 0.0, delta=1e-12)

    def test_fully_dry_and_pressure_gradient_zero(self):
        self.assertEqual(tetra_buoyancy(-0.5), (0, 0, 0))
        self.assertEqual(net_force((A, B, D), 2, 0), (0, 0, 0))

    def test_exact_barycentric_force_partition_for_clipped_face(self):
        points = ((0, -1, 0), (1, 1, 0), (0, 1, 1))
        f = hydrostatic_triangle(points, 0, 12)
        m = math.dist(f[0], (0, 0, 0))
        n = math.dist(f[1], (0, 0, 0))
        z = math.dist(f[2], (0, 0, 0))
        self.assertAlmostEqual(m/n, 6, places=12)
        self.assertAlmostEqual(n/z, 1, places=12)

    def test_reversed_winding_and_signed_volume_correction(self):
        rng = random.Random(10931)
        for _ in range(200):
            water = rng.uniform(-1.0, 2.0)
            for a, b, c in TETRA_FACES:
                normal = net_force((a, b, c), water, 9810, 1)
                reversed_face = net_force((a, c, b), water, 9810, -1)
                for j in range(3):
                    self.assertAlmostEqual(normal[j], reversed_face[j], delta=1e-10)

    def test_density_and_gravity_scale_forces_linearly(self):
        for water in (0.1, 0.33, 0.5, 1.0, 2.0):
            baseline = tetra_buoyancy(water, 9.81)
            twice = tetra_buoyancy(water, 19.62)
            for j in range(3):
                self.assertAlmostEqual(twice[j], baseline[j] * 2, delta=1e-12)

    def test_rotated_and_translated_tetrahedron_still_floats_up(self):
        rng = random.Random(0xABCD)
        for _ in range(300):
            angle = rng.uniform(-math.pi, math.pi)
            ct, st = math.cos(angle), math.sin(angle)
            shift = (rng.uniform(-10, 10), rng.uniform(-10, 10), rng.uniform(-10, 10))
            def move(p):
                return (ct*p[0] - st*p[2] + shift[0],
                        p[1] + shift[1],
                        st*p[0] + ct*p[2] + shift[2])
            transformed = [(move(a), move(b), move(c)) for a, b, c in TETRA_FACES]
            force = tuple(sum(net_force(tri, shift[1]+3, 6)[j]
                              for tri in transformed) for j in range(3))
            self.assertAlmostEqual(force[0], 0, delta=1e-11)
            self.assertAlmostEqual(force[1], 1, delta=1e-11)
            self.assertAlmostEqual(force[2], 0, delta=1e-11)

    def test_native_closed_mesh_and_project_setting_contracts(self):
        cpp = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.cpp").read_text()
        header = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.h").read_text()
        space_h = (ROOT / "modules/godot_physics_3d/godot_space_3d.h").read_text()
        space_cpp = (ROOT / "modules/godot_physics_3d/godot_space_3d.cpp").read_text()
        server = (ROOT / "servers/physics_3d/physics_server_3d.cpp").read_text()
        solver_header = (ROOT / "servers/physics_softbody_hydrostatic.h").read_text()
        self.assertIn("physics/3d/solver/soft_body_hydrostatic_pressure", server)
        self.assertIn("soft_body_hydrostatic_pressure = false;", space_h)
        self.assertIn('GLOBAL_GET("physics/3d/solver/soft_body_hydrostatic_pressure")', space_cpp)
        self.assertIn("apply_hydrostatic_forces(const Vector3 &p_gravity)", header)
        self.assertIn("!xpbd_volume_closed", cpp)
        self.assertIn("is_fluid_plane_enabled()", cpp)
        self.assertIn("physics_softbody_hydrostatic_face_forces(", cpp)
        self.assertIn("pressure_gradient", solver_header)
        self.assertIn("get_fluid_plane_surface_height()", cpp)
        self.assertIn("get_fluid_plane_density()", cpp)
        self.assertIn("!(get_space()->is_soft_body_hydrostatic_pressure_enabled()", cpp)
        body = cpp.index("void GodotSoftBody3D::predict_motion(")
        pressure = cpp.index("apply_hydrostatic_forces(gravity)", body)
        integrate = cpp.index("for (Node &node : nodes)", pressure)
        self.assertLess(pressure, integrate)


if __name__ == "__main__":
    unittest.main()
