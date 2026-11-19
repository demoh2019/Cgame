"""Numerical and source contracts for mesh-local orthotropic XPBD bending.

The C++ code reuses the validated directional stretch compliance law to
scale the *dihedral hinge* based on its original shared-edge direction.
This Python model independently checks material behavior and topology wiring.
Run:
    python3 -m unittest discover -s tests/stress -p 'test_physics_xpbd_orthotropic_bending.py' -v
"""

import math
from pathlib import Path
import random
import unittest

ROOT = Path(__file__).resolve().parents[2]


def bend_alpha(crease, fiber, baseline, parallel_ratio):
    """A hinge bends about the crease direction; alignment is cosine squared."""
    if parallel_ratio == 1 or baseline == 0:
        return baseline
    l1 = math.sqrt(sum(x*x for x in crease))
    l2 = math.sqrt(sum(x*x for x in fiber))
    if not l1:
        return baseline
    if not l2:
        raise ValueError("material fiber axis must be nonzero")
    cos = sum(a*b for a, b in zip(crease, fiber)) / l1 / l2
    aligned = max(0.0, min(1.0, cos*cos))
    return baseline*(1.0+(parallel_ratio-1.0)*aligned)


def xpbd_angle_step(error, alpha, inv_weight=1.0, iterations=12):
    """Linearized XPBD angular correction with a step-local multiplier."""
    lagrange = 0.0
    for _ in range(iterations):
        d_lambda = -(error+alpha*lagrange)/(inv_weight+alpha)
        error += d_lambda*inv_weight
        lagrange += d_lambda
    return error


class TestXPBDOrthotropicBending(unittest.TestCase):
    def test_directional_bending_soft_hard_and_diagonal(self):
        self.assertAlmostEqual(bend_alpha((2, 0, 0), (1, 0, 0), 1, 0.2), 0.2)
        self.assertAlmostEqual(bend_alpha((0, 0, 2), (1, 0, 0), 1, 0.2), 1.0)
        self.assertAlmostEqual(bend_alpha((2, 0, 2), (1, 0, 0), 1, 0.2), 0.6)
        self.assertAlmostEqual(bend_alpha((2, 0, 0), (1, 0, 0), 1, 3.0), 3.0)

    def test_one_is_bit_exact_legacy_behavior(self):
        rng = random.Random(0xBEE5)
        for _ in range(4000):
            crease = tuple(rng.uniform(-10, 10) for _ in range(3))
            axis = tuple(rng.uniform(-10, 10) for _ in range(3))
            base = 10 ** rng.uniform(-9, 2)
            self.assertEqual(bend_alpha(crease, axis, base, 1), base)

    def test_random_material_rotation_invariance(self):
        rng = random.Random(0x1EC1)
        for _ in range(5000):
            angle = rng.uniform(-math.pi, math.pi)
            c, s = math.cos(angle), math.sin(angle)
            crease = tuple(rng.uniform(-10, 10) for _ in range(3))
            fiber = tuple(rng.uniform(-10, 10) for _ in range(3))
            ratio = 10 ** rng.uniform(-2, 2)
            rotate = lambda v: (c*v[0]-s*v[2], v[1], s*v[0]+c*v[2])
            original = bend_alpha(crease, fiber, 0.03, ratio)
            rotated = bend_alpha(rotate(crease), rotate(fiber), 0.03, ratio)
            self.assertAlmostEqual(original, rotated, delta=1e-12*(1+abs(original)))

    def test_random_alignment_bounds_and_rest_edge_reversal(self):
        rng = random.Random(0xC0CA)
        for _ in range(8000):
            crease = tuple(rng.uniform(-20, 20) for _ in range(3))
            axis = tuple(rng.uniform(-20, 20) for _ in range(3))
            ratio = 10 ** rng.uniform(-2, 2)
            base = 10 ** rng.uniform(-7, 1)
            value = bend_alpha(crease, axis, base, ratio)
            self.assertGreaterEqual(value, base*min(ratio, 1)-1e-12)
            self.assertLessEqual(value, base*max(ratio, 1)+1e-12)
            self.assertAlmostEqual(
                value, bend_alpha(tuple(-c for c in crease), axis, base, ratio),
                delta=1e-12*(1+value))

    def test_hinge_stiffness_depends_on_rest_crease_not_live_fold(self):
        # When the fold rotates the shared edge toward another direction,
        # material stiffness must remain tied to the original edge.
        rest_crease = (2, 1, 0)
        axis = (1, 0, 0)
        rest_alpha = bend_alpha(rest_crease, axis, 0.5, 0.2)
        for current_crease in ((0, 1, 2), (0, 1, -2), (0.01, 1, 3)):
            current_alpha = bend_alpha(current_crease, axis, 0.5, 0.2)
            self.assertNotAlmostEqual(current_alpha, rest_alpha, places=3)
            # Hinge initialization computes from rest only; deformations
            # must not update the cached material ratio.
            self.assertEqual(bend_alpha(rest_crease, axis, 0.5, 0.2), rest_alpha)

    def test_stiffer_bending_reduces_linearized_angular_error(self):
        before = math.pi/5
        stiff = bend_alpha((1, 0, 0), (1, 0, 0), 1, 0.1)
        soft = bend_alpha((1, 0, 0), (1, 0, 0), 1, 5.0)
        self.assertLess(abs(xpbd_angle_step(before, stiff)),
                        abs(xpbd_angle_step(before, soft)))
        self.assertLess(abs(xpbd_angle_step(before, soft)), abs(before))

    def test_pinned_crease_can_fold_without_moving_shared_edge(self):
        # The XPBD dihedral kernel takes inverse masses for all four nodes;
        # zero inverse masses keep the shared crease and third pin fixed.
        crease_inverse_mass = (0, 0, 0, 1)
        self.assertEqual(crease_inverse_mass[:3], (0, 0, 0))
        self.assertGreater(sum(crease_inverse_mass), 0)

    def test_runtime_wiring_and_backward_compatibility(self):
        server = (ROOT / "servers/physics_3d/physics_server_3d.cpp").read_text()
        space = (ROOT / "modules/godot_physics_3d/godot_space_3d.cpp").read_text()
        space_h = (ROOT / "modules/godot_physics_3d/godot_space_3d.h").read_text()
        body = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.cpp").read_text()
        body_h = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.h").read_text()
        name = "soft_body_xpbd_bend_parallel_compliance_ratio"
        self.assertIn(f'"physics/3d/solver/{name}"', server)
        self.assertIn(f'GLOBAL_GET("physics/3d/solver/{name}")', space)
        self.assertIn(f"{name} = 1.0;", space_h)
        self.assertIn("get_soft_body_xpbd_bend_parallel_compliance_ratio()", space_h)
        self.assertIn("bend_compliance_ratio = 1.0;", body_h)
        self.assertIn("nodes[edge.a].s, nodes[edge.b].s", body)
        self.assertIn("get_soft_body_xpbd_material_axis()", body)
        self.assertIn("physics_xpbd_anisotropic_stretch_alpha(", body)
        self.assertIn("if (bend_ratio != real_t(1.0))", body)
        self.assertIn("if (hinge.bend_compliance_ratio != real_t(1.0))", body)
        self.assertIn("hinge_alpha, xpbd_dihedral_lambdas[hinge_index]", body)
        self.assertIn("physics_xpbd_solve_dihedral(a.x, b.x, c.x, d.x,", body)
        # We cache directional compliance at topology construction, NEVER
        # recompute alignment inside the iterative solver.
        topo = body.index("void GodotSoftBody3D::initialize_dihedral_constraints()")
        solve = body.index("void GodotSoftBody3D::solve_constraints(")
        self.assertLess(body.index("nodes[edge.a].s, nodes[edge.b].s", topo), solve)


if __name__ == "__main__":
    unittest.main()
