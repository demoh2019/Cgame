"""Numerical and source contracts for opt-in XPBD dihedral cloth bending.

The finite-difference tests validate the analytical angle Jacobian. The
companion GDScript workload requires a compiled Cgame GodotPhysics3D binary.
"""

import math
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
STRESS = ROOT / "tests/stress"


def sub(a, b):
    return tuple(x - y for x, y in zip(a, b))


def cross(a, b):
    return (
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    )


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def norm(a):
    return math.sqrt(dot(a, a))


def scale(a, amount):
    return tuple(x * amount for x in a)


def add(a, b):
    return tuple(x + y for x, y in zip(a, b))


def hinge_angle(points):
    a, b, c, d = points
    edge = sub(b, a)
    nc = cross(edge, sub(c, a))
    nd = cross(sub(d, a), edge)
    edge_len = norm(edge)
    lc, ld = norm(nc), norm(nd)
    if min(edge_len, lc, ld) < 1e-10:
        raise ValueError("Degenerate hinge")
    ehat = scale(edge, 1. / edge_len)
    nhat_c, nhat_d = scale(nc, 1. / lc), scale(nd, 1. / ld)
    return math.atan2(dot(ehat, cross(nhat_c, nhat_d)), dot(nhat_c, nhat_d))


def hinge_gradients(points):
    a, b, c, d = points
    edge = sub(b, a)
    edge_sq = dot(edge, edge)
    nc = cross(edge, sub(c, a))
    nd = cross(sub(d, a), edge)
    length = math.sqrt(edge_sq)
    gc = scale(nc, -length / dot(nc, nc))
    gd = scale(nd, -length / dot(nd, nd))
    ga = add(scale(gc, dot(sub(c, b), edge) / edge_sq),
             scale(gd, dot(sub(d, b), edge) / edge_sq))
    gb = add(scale(gc, dot(sub(a, c), edge) / edge_sq),
             scale(gd, dot(sub(a, d), edge) / edge_sq))
    return ga, gb, gc, gd


def project_hinge(points, inv_masses, rest_angle, alpha, lagrange=0.):
    angle = hinge_angle(points)
    grads = hinge_gradients(points)
    total = sum(w * dot(g, g) for w, g in zip(inv_masses, grads))
    if total <= 0.0:
        return tuple(points), lagrange
    error = angle - rest_angle
    if error > math.pi:
        error -= 2. * math.pi
    elif error < -math.pi:
        error += 2. * math.pi
    delta_l = -(error + alpha * lagrange) / (total + alpha)
    result = tuple(add(x, scale(g, w * delta_l))
                   for x, g, w in zip(points, grads, inv_masses))
    return result, lagrange + delta_l


class XPBDDihedralContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.helper = (ROOT / "servers/physics_xpbd_dihedral.h").read_text(encoding="utf-8")
        cls.cpp = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.cpp").read_text(encoding="utf-8")
        cls.header = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.h").read_text(encoding="utf-8")
        cls.space = (ROOT / "modules/godot_physics_3d/godot_space_3d.cpp").read_text(encoding="utf-8")
        cls.space_header = (ROOT / "modules/godot_physics_3d/godot_space_3d.h").read_text(encoding="utf-8")
        cls.settings = (ROOT / "servers/physics_3d/physics_server_3d.cpp").read_text(encoding="utf-8")

    def test_analytic_gradients_match_finite_differences(self):
        for points in (
            ((0., 0., 0.), (2., 0., 0.), (0., 1., 0.), (1., -1., 0.2)),
            ((1., 2., 3.), (0., 1., 0.), (2., 1., 4.), (-2., 1., 3.)),
            ((-0.2, 0.8, 0.1), (1.5, -0.2, 0.8), (0.7, 1.2, -0.1), (0.4, -0.6, -0.5)),
        ):
            gradients = hinge_gradients(points)
            for particle in range(4):
                for axis in range(3):
                    plus = [list(p) for p in points]
                    minus = [list(p) for p in points]
                    plus[particle][axis] += 1e-6
                    minus[particle][axis] -= 1e-6
                    numerical = (hinge_angle(plus) - hinge_angle(minus)) / (2e-6)
                    self.assertAlmostEqual(gradients[particle][axis], numerical, delta=2e-6)

    def test_translation_invariant_gradients(self):
        points = ((0., 0., 0.), (2., 0., 0.), (0., 1., 0.), (0., -1., 0.4))
        gradients = hinge_gradients(points)
        for axis in range(3):
            self.assertAlmostEqual(sum(g[axis] for g in gradients), 0., delta=1e-10)
        shifted = tuple(add(p, (1000., -300., 800.)) for p in points)
        self.assertAlmostEqual(hinge_angle(points), hinge_angle(shifted), delta=1e-12)

    def test_pins_and_nonflat_rest_angle_projection(self):
        points = ((-1., 0., 0.), (1., 0., 0.), (0., 1., 0.), (0., -1., 0.7))
        pinned = (0., 0., 0., 4.)
        before = abs(hinge_angle(points))
        after, lam = project_hinge(points, pinned, 0., 0.0036)
        self.assertEqual(points[:3], after[:3])
        self.assertLess(abs(hinge_angle(after)), before * 0.2)
        self.assertTrue(math.isfinite(lam))
        # A folded mesh can preserve a NONZERO rest angle too.
        curved = ((-1., 0., 0.), (1., 0., 0.), (0., 1., 0.), (0., -1., 0.3))
        rest = hinge_angle(curved)
        self.assertAlmostEqual(hinge_angle(curved), rest)
        unchanged, _ = project_hinge(curved, pinned, rest, 0.0036)
        self.assertEqual(unchanged, curved)

    def test_topology_rejects_boundaries_nonmanifold_and_winding(self):
        def valid_hinges(faces):
            edges = {}
            for triangle in faces:
                for i in range(3):
                    a, b, c = triangle[i], triangle[(i + 1) % 3], triangle[(i + 2) % 3]
                    if len({a, b, c}) != 3:
                        continue
                    edges.setdefault(tuple(sorted((a, b))), []).append((a, b, c))
            return [records for records in edges.values()
                    if len(records) == 2 and records[0][0] == records[1][1]
                    and records[0][1] == records[1][0] and records[0][2] != records[1][2]]
        self.assertEqual(len(valid_hinges([(0, 1, 2), (1, 0, 3)])), 1)
        self.assertEqual(len(valid_hinges([(0, 1, 2)])), 0)
        self.assertEqual(len(valid_hinges([(0, 1, 2), (0, 1, 3)])), 0)
        self.assertEqual(len(valid_hinges([(0, 1, 2), (1, 0, 3), (0, 1, 4)])), 0)

    def test_helper_rejects_degenerate_invalid_and_preserves_atomicity(self):
        self.assertIn("physics_xpbd_dihedral_angle(", self.helper)
        self.assertIn("physics_xpbd_solve_dihedral(", self.helper)
        self.assertIn("r_angle = Math::atan2(sine, cosine);", self.helper)
        self.assertIn("p_inv_a < 0.0", self.helper)
        self.assertIn("!(edge_squared > CMP_EPSILON * CMP_EPSILON)", self.helper)
        self.assertIn("const Vector3 grad_c = normal_c * (-edge_length / nc_sq);", self.helper)
        self.assertIn("const Vector3 grad_d = normal_d * (-edge_length / nd_sq);", self.helper)
        self.assertIn("Math::is_finite(next_lambda)", self.helper)
        self.assertIn("!next_a.is_finite() || !next_b.is_finite()", self.helper)
        self.assertIn("r_a = next_a;\n\tr_b = next_b;\n\tr_c = next_c;\n\tr_d = next_d;", self.helper)

    def test_integration_opt_in_stable_mesh_topology_and_per_step_lambdas(self):
        self.assertIn('"physics/3d/solver/soft_body_xpbd_dihedral_compliance"', self.settings)
        self.assertIn("soft_body_xpbd_dihedral_compliance = 0.0;", self.space_header)
        self.assertIn('GLOBAL_GET("physics/3d/solver/soft_body_xpbd_dihedral_compliance")', self.space)
        self.assertIn("LocalVector<DihedralHinge> xpbd_dihedral_hinges;", self.header)
        self.assertIn("LocalVector<real_t> xpbd_dihedral_lambdas;", self.header)
        self.assertIn("void GodotSoftBody3D::initialize_dihedral_constraints()", self.cpp)
        self.assertIn("entry.count = 3; // Non-manifold", self.cpp)
        self.assertIn("edge.count != 2 || !edge.correctly_wound", self.cpp)
        self.assertIn("initialize_dihedral_constraints();", self.cpp)
        self.assertIn("xpbd_dihedral_lambdas.resize(xpbd_dihedral_hinges.size());", self.cpp)
        self.assertIn("physics_xpbd_solve_dihedral(a.x, b.x, c.x, d.x,", self.cpp)
        self.assertIn("xpbd_dihedral_lambdas.reset();", self.cpp)
        self.assertIn("xpbd_dihedral_hinges.reset();", self.cpp)
        self.assertIn("physics_xpbd_solve_triangle_area(", self.cpp)
        self.assertIn("solve_volume_constraint(volume_alpha, volume_lambda);", self.cpp)
        self.assertIn("solve_links(1.0, ti);", self.cpp)

    def test_real_bending_stress_is_registered_and_isolated(self):
        case = "physics_soft_body_xpbd_dihedral_3d"
        self.assertIn(f'"{case}"', (STRESS / "run.py").read_text(encoding="utf-8"))
        self.assertIn(f'"{case}":', (STRESS / "stress.gd").read_text(encoding="utf-8"))
        workload = (STRESS / (case + ".gd")).read_text(encoding="utf-8")
        self.assertIn("soft_body_set_linear_stiffness(body, 0.0)", workload)
        self.assertIn("soft_body_pin_point(body, index, true)", workload)
        self.assertIn("var malformed: Dictionary =", workload)
        self.assertIn("bent.mean_angle < baseline.mean_angle * 0.25", workload)
        self.assertIn("malformed.mean_angle > 0.4", workload)
        self.assertIn('3d/physics_engine="GodotPhysics3D"', (STRESS / "project.godot").read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
