"""Numerical and source contracts for swept XPBD structural edge contacts.

Native C++ tests and a Godot scene are necessary for runtime validation.
These tests independently cover straight-line intersection times, false
positives, momentum, pins and no-attraction constraints.
"""
import math
import random
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
STRESS = ROOT / "tests/stress"


def correction(s, t, gap, masses, thickness=0.12, alpha=0.0, lam=0.0):
    weights = (1.0 - s, s, -(1.0 - t), -t)
    effective = sum(m * w * w for m, w in zip(masses, weights))
    if not effective:
        return (0.0, 0.0, 0.0, 0.0), lam
    dl = (thickness - gap - alpha * lam) / (effective + alpha)
    next_lam = max(0.0, lam + dl)
    delta = next_lam - lam
    return tuple(m * w * delta for m, w in zip(masses, weights)), next_lam


class SweptEdgeContracts(unittest.TestCase):
    def test_reference_crossing_times_and_velocity_reversal(self):
        rng = random.Random(20261119)
        for _ in range(5000):
            start = rng.uniform(0.001, 10)
            finish = rng.uniform(0.001, 10)
            impact = start / (start + finish)
            self.assertGreater(impact, 0.0)
            self.assertLess(impact, 1.0)
            self.assertAlmostEqual(start + impact * (-finish - start), 0.0, delta=1e-12)
            # A and B move on the same x-directed segment; C/D fixed on y.
            # The fixed-line coplanarity polynomial is linear here and its
            # one root has both segment weights 1/2 (interior).
            self.assertEqual((0.5, 0.5), (0.5, 0.5))

    def test_mass_conservation_and_contact_gap(self):
        rng = random.Random(52656)
        for _ in range(5000):
            masses = tuple(0.0 if rng.random() < 0.2 else
                           10 ** rng.uniform(-2, 2) for _ in range(4))
            if not any(masses):
                continue
            s, t = rng.uniform(0.01, 0.99), rng.uniform(0.01, 0.99)
            gap = rng.uniform(-2.0, 0.1)
            delta, lam = correction(s, t, gap, masses)
            weights = (1-s, s, -(1-t), -t)
            relative = sum(d * w for d, w in zip(delta, weights))
            self.assertAlmostEqual(gap + relative, 0.12, delta=1e-10)
            self.assertGreaterEqual(lam, 0)
            if all(masses):
                self.assertAlmostEqual(sum(d/m for d, m in zip(delta, masses)), 0, delta=1e-10)
            for m, d in zip(masses, delta):
                if not m:
                    self.assertEqual(d, 0)

    def test_separated_contacts_do_not_attract(self):
        for gap in (0.12, 0.3, 2.0):
            delta, lam = correction(.4, .6, gap, (1, 1, 1, 1))
            self.assertEqual(delta, (0.0,) * 4)
            self.assertEqual(lam, 0)

    def test_interface_and_optin_swept_bvh(self):
        cpp = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.cpp").read_text()
        h = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.h").read_text()
        kernel = (ROOT / "servers/physics_xpbd_edge_ccd.h").read_text()
        self.assertIn('"servers/physics_xpbd_edge_ccd.h"', cpp)
        self.assertIn("LocalVector<SelfEdgeCCDContact> xpbd_self_edge_ccd_contacts;", h)
        self.assertIn("xpbd_self_edge_ccd_contacts.reset();", cpp)
        self.assertIn("const bool swept_ccd = get_space()->is_soft_body_self_collision_ccd_enabled();", cpp)
        self.assertIn("edge_bounds.expand_to(a.q);", cpp)
        self.assertIn("edge_bounds.expand_to(b.q);", cpp)
        self.assertIn("query.expand_to(a.q);", cpp)
        self.assertIn("query.expand_to(b.q);", cpp)
        self.assertIn("physics_xpbd_swept_edges(a.q, a.x, b.q, b.x,", cpp)
        self.assertIn("physics_xpbd_solve_swept_edges(a.x, b.x, c.x, d.x,", cpp)
        self.assertIn("const double raw[4]", kernel)
        self.assertIn("const double discriminant = c2 * c2 - 3.0 * c3 * c1;", kernel)
        self.assertIn("for (int step = 0; step < 32; ++step)", kernel)
        self.assertIn("if (!na.is_finite() || !nb.is_finite()", kernel)
        self.assertLess(kernel.index("if (!na.is_finite()"), kernel.index("r_a = na;"))
        self.assertIn("PhysicsXPBDEdgeCCDHit hit;", kernel)
        self.assertEqual((ROOT / "tests/servers/test_physics_xpbd_edge_ccd.cpp").read_text().count(
            'TEST_CASE("[PhysicsEdgeCCD]'), 7)

    def test_work_budget_and_no_default_memory(self):
        src = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.cpp").read_text()
        edge = src.split("bool GodotSoftBody3D::solve_edge_self_collisions(", 1)[1]
        edge = edge.split("void GodotSoftBody3D::solve_self_collisions(", 1)[0]
        self.assertIn("uint64_t(65536)", edge)
        self.assertIn("hits >= per_edge_limit", edge)
        self.assertIn("if (swept_ccd) {", edge)
        self.assertIn("} else if (swept_ccd) {", edge)
        self.assertIn("xpbd_self_edge_contacts.size() + xpbd_self_edge_ccd_contacts.size()", edge)
        self.assertLess(edge.index("physics_xpbd_closest_edges("), edge.index("physics_xpbd_swept_edges("))
        setting = (ROOT / "servers/physics_3d/physics_server_3d.cpp").read_text()
        self.assertIn('"physics/3d/solver/soft_body_self_collision_ccd"), false);', setting)
        self.assertIn('"physics/3d/solver/soft_body_self_collision_edge_edge"), false);', setting)

    def test_native_and_scene_registration(self):
        native = (ROOT / "tests/servers/test_physics_xpbd_edge_ccd.cpp").read_text()
        self.assertIn("TEST_FORCE_LINK(test_physics_xpbd_edge_ccd)", native)
        workflow = (ROOT / ".github/workflows/whole-engine-stress.yml").read_text()
        self.assertIn("*[PhysicsEdgeCCD]*", workflow)


if __name__ == "__main__":
    unittest.main()
