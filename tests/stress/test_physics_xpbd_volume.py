"""Source and numerical regressions for closed soft-body XPBD volume.

These tests do not require a built engine. The paired GDScript stress case
asserts closed-volume recovery and rejects open meshes at runtime.
"""

import math
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
STRESS = ROOT / "tests/stress"
FACES = [(0, 2, 1), (0, 1, 3), (0, 3, 2), (1, 2, 3)]
TETRA = [(0.0, 0.0, 0.0), (2.0, 0.0, 0.0),
         (0.0, 2.0, 0.0), (0.0, 0.0, 2.0)]


def sub(a, b):
    return tuple(x - y for x, y in zip(a, b))


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1],
            a[2] * b[0] - a[0] * b[2],
            a[0] * b[1] - a[1] * b[0])


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def volume(vertices, faces=FACES):
    origin = vertices[0]
    return sum(dot(sub(vertices[a], origin),
                   cross(sub(vertices[b], origin), sub(vertices[c], origin))) / 6.
               for a, b, c in faces)


def gradients(vertices, faces=FACES):
    origin = vertices[0]
    accum = [[0., 0., 0.] for _ in vertices]
    for a, b, c in faces:
        u, v, w = (sub(vertices[i], origin) for i in (a, b, c))
        for index, grad in ((a, cross(v, w)), (b, cross(w, u)),
                            (c, cross(u, v))):
            for axis in range(3):
                accum[index][axis] += grad[axis] / 6.
    return accum


def oriented_closed(faces):
    # Mirrors the implementation's two opposing half-edge flags.
    winding = {}
    for a, b, c in faces:
        for frm, to in ((a, b), (b, c), (c, a)):
            if frm == to:
                return False
            key = (min(frm, to), max(frm, to))
            direction = 1 if frm < to else 2
            if winding.get(key, 0) & direction:
                return False
            winding[key] = winding.get(key, 0) | direction
    return all(bits == 3 for bits in winding.values())


class SoftBodyXPBDVolumeContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cpp = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.cpp").read_text(encoding="utf-8")
        cls.header = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.h").read_text(encoding="utf-8")
        cls.space = (ROOT / "modules/godot_physics_3d/godot_space_3d.cpp").read_text(encoding="utf-8")
        cls.space_h = (ROOT / "modules/godot_physics_3d/godot_space_3d.h").read_text(encoding="utf-8")
        cls.settings = (ROOT / "servers/physics_3d/physics_server_3d.cpp").read_text(encoding="utf-8")

    def test_closed_mesh_validation_accepts_tetra_and_rejects_open_or_nonmanifold(self):
        self.assertTrue(oriented_closed(FACES))
        self.assertFalse(oriented_closed(FACES[:-1]))
        self.assertFalse(oriented_closed(FACES + [FACES[0]]))
        self.assertFalse(oriented_closed(FACES[:1] + [tuple(reversed(FACES[1]))] + FACES[2:]))
        self.assertAlmostEqual(volume(TETRA), 4. / 3.)
        self.assertAlmostEqual(volume(TETRA, [tuple(reversed(f)) for f in FACES]), -4. / 3.)

    def test_closed_volume_gradients_agree_with_finite_difference(self):
        points = [(0.1, 0.2, 0.3), (2.0, -0.1, 0.4),
                  (0.0, 2.1, -0.3), (-0.3, 0.1, 2.0)]
        grad = gradients(points)
        for vertex in range(4):
            for axis in range(3):
                perturbed = [list(p) for p in points]
                h = 1e-5
                perturbed[vertex][axis] += h
                forward = volume(perturbed)
                perturbed[vertex][axis] -= 2 * h
                backward = volume(perturbed)
                self.assertAlmostEqual((forward - backward) / (2*h),
                                       grad[vertex][axis], delta=1e-8)

    def test_volume_projection_recovers_pinned_tetra(self):
        points = [list(p) for p in TETRA]
        rest = volume(points)
        points[3][2] = 0.6
        old_error = abs(volume(points) - rest)
        inv_mass = [0., 0., 0., 4.]
        alpha = 1.e-8 / (1./60.)**2
        g = gradients(points)
        denom = sum(inv_mass[i] * dot(g[i], g[i]) for i in range(4)) + alpha
        dl = -(volume(points) - rest) / denom
        next_positions = [
            [points[i][c] + inv_mass[i] * dl * g[i][c] for c in range(3)]
            for i in range(4)
        ]
        self.assertEqual(next_positions[:3], [list(p) for p in TETRA[:3]])
        self.assertLess(abs(volume(next_positions) - rest), old_error * .01)

    def test_opt_in_settings_and_lifecycle(self):
        self.assertIn('GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/soft_body_xpbd_volume_compliance"', self.settings)
        self.assertIn('"0,0.01,0.000001,or_greater"), 0.0);', self.settings)
        self.assertIn("soft_body_xpbd_volume_compliance = 0.0;", self.space_h)
        self.assertIn("get_soft_body_xpbd_volume_compliance()", self.space_h)
        self.assertIn('GLOBAL_GET("physics/3d/solver/soft_body_xpbd_volume_compliance")', self.space)
        self.assertIn("Math::is_finite(configured_volume_compliance)", self.space)
        self.assertIn("LocalVector<Vector3> xpbd_volume_gradients;", self.header)
        self.assertIn("double xpbd_volume_rest = 0.0;", self.header)
        self.assertIn("bool xpbd_volume_closed = false;", self.header)
        self.assertIn("initialize_volume_constraint();", self.cpp)
        self.assertIn("void GodotSoftBody3D::initialize_volume_constraint()", self.cpp)
        self.assertIn("bool GodotSoftBody3D::solve_volume_constraint(", self.cpp)
        self.assertIn("const bool use_volume_xpbd =", self.cpp)
        self.assertIn("xpbd_volume_gradients.resize(nodes.size());", self.cpp)
        self.assertIn("xpbd_volume_gradients.reset();", self.cpp)
        self.assertIn("solve_volume_constraint(volume_alpha, volume_lambda);", self.cpp)

    def test_safety_checks_and_topology_fallback(self):
        self.assertIn("HashMap<uint64_t, uint8_t> edge_winding;", self.cpp)
        self.assertIn("existing->value & direction", self.cpp)
        self.assertIn("entry.value != uint8_t(3)", self.cpp)
        self.assertIn("xpbd_volume_closed = true;", self.cpp)
        self.assertIn("if (!xpbd_volume_closed || !(p_alpha > 0.0)", self.cpp)
        self.assertIn("if (!Math::is_finite(volume))", self.cpp)
        self.assertIn("if (!next.is_finite())", self.cpp)
        self.assertIn("if (node.im == 0.0)", self.cpp)
        self.assertIn("r_lambda = next_lambda;", self.cpp)

    def test_runtime_registration_and_closed_open_comparison(self):
        case = "physics_soft_body_xpbd_volume_3d"
        self.assertIn(f'"{case}"', (STRESS / "run.py").read_text(encoding="utf-8"))
        self.assertIn(f'"{case}":', (STRESS / "stress.gd").read_text(encoding="utf-8"))
        workload = (STRESS / f"{case}.gd").read_text(encoding="utf-8")
        self.assertIn("PhysicsServer3D.soft_body_pin_point(body, 0, true)", workload)
        self.assertIn("PhysicsServer3D.soft_body_pin_point(body, 2, true)", workload)
        self.assertIn("PhysicsServer3D.soft_body_move_point(body, 3", workload)
        self.assertIn("var open_surface: Dictionary =", workload)
        self.assertIn("open_surface.mean_volume_error > 0.5", workload)
        self.assertIn('3d/physics_engine="GodotPhysics3D"', (STRESS / "project.godot").read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
