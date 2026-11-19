"""Reference tests for inter-SoftBody3D XPBD edge/edge contacts.

The native implementation shares the existing edge-edge constraint but
updates velocities after each position correction. The reference checks
conservation, unilateral separation, pinning and configuration wiring.
"""
from pathlib import Path
import random
import unittest

ROOT = Path(__file__).resolve().parents[2]


def solve_contact(z_first, z_second, inverse_masses, thickness, dt, compliance):
    # Two perpendicular structural edges, closest points at s=t=1/2.
    normal = 1.0 if z_first >= z_second else -1.0
    separation = normal * (z_first - z_second)
    s, t = 0.5, 0.5
    weights = (1-s, s, -(1-t), -t)
    weighted_mass = sum(w*w*inv for w, inv in zip(weights, inverse_masses))
    if weighted_mass <= 0:
        return None
    lam = max(0.0, (thickness-separation) / (weighted_mass+compliance/(dt*dt)))
    corrections = tuple(normal * mass * weight * lam
                        for mass, weight in zip(inverse_masses, weights))
    return corrections, tuple(x / dt for x in corrections), lam


class TestSoftSoftEdgeContact(unittest.TestCase):
    def test_randomized_4000_contacts_and_momentum(self):
        rng = random.Random(0xED9EC0DE)
        for _ in range(4000):
            thickness = rng.uniform(0.01, 0.25)
            gap = rng.uniform(0.0, thickness * 0.95)
            side = rng.choice((-1, 1))
            inv = tuple(rng.uniform(.1, 5) for _ in range(4))
            dt = rng.uniform(1/240, 1/24)
            compliance = rng.choice((0.0, 0.000001))
            result = solve_contact(0.0, -side*gap, inv, thickness, dt, compliance)
            self.assertIsNotNone(result)
            changes, velocities, lam = result
            self.assertGreater(lam, 0)
            self.assertAlmostEqual(sum(changes[i]/inv[i] for i in range(4)),
                                   0.0, delta=1e-10)
            for i in range(4):
                self.assertAlmostEqual(changes[i]/dt, velocities[i], delta=1e-10)
            # Inverse masses weight the corrections in opposite directions.
            relative_change = (changes[0]+changes[1]-changes[2]-changes[3])/2
            self.assertGreaterEqual(side * relative_change, 0.0)
            if compliance == 0.0:
                self.assertAlmostEqual(side*gap + side*relative_change,
                                       thickness, delta=1e-9)

    def test_pinned_edge_and_compliance(self):
        out = solve_contact(0.0, 0.02, (0.0, 0.0, 1.0, 1.0),
                            0.1, 0.02, 0.0)
        self.assertEqual(out[0][0], 0.0)
        self.assertEqual(out[0][1], 0.0)
        self.assertGreater(out[0][2], 0.0)
        self.assertGreater(out[0][3], 0.0)
        fully_pinned = solve_contact(0.0, 0.02, (0.0,)*4, 0.1, 0.02, 0.0)
        self.assertIsNone(fully_pinned)
        stiff = solve_contact(0.0, 0.02, (1.0,)*4, 0.1, 0.02, 0.0)
        compliant = solve_contact(0.0, 0.02, (1.0,)*4, 0.1, 0.02, 0.001)
        self.assertLess(compliant[2], stiff[2])

    def test_source_wiring_and_disabled_default(self):
        h = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.h").read_text()
        cpp = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.cpp").read_text()
        space_h = (ROOT / "modules/godot_physics_3d/godot_space_3d.h").read_text()
        space_cpp = (ROOT / "modules/godot_physics_3d/godot_space_3d.cpp").read_text()
        server = (ROOT / "servers/physics_3d/physics_server_3d.cpp").read_text()
        helper = (ROOT / "servers/physics_softbody_pair_edge_contact.h").read_text()
        self.assertIn('"physics/3d/solver/soft_body_pair_collision_edge_edge"), false', server)
        self.assertIn('soft_body_pair_collision_edge_edge = false;', space_h)
        self.assertIn('soft_body_pair_collision_edge_edge = GLOBAL_GET(', space_cpp)
        self.assertIn('DynamicBVH xpbd_pair_edge_tree;', h)
        self.assertIn('LocalVector<SelfCollisionEdge> xpbd_pair_edges;', h)
        self.assertIn('HashSet<uint64_t> seen;', cpp)
        self.assertIn('xpbd_pair_edge_tree.update(', cpp)
        self.assertIn('p_other.xpbd_pair_edge_tree.aabb_query(', cpp)
        self.assertIn('solve_pair_edge_contacts(p_other, p_delta', cpp)
        self.assertIn('is_soft_body_pair_collision_edge_edge_enabled()', cpp)
        self.assertIn('physics_xpbd_solve_edge_collision(', helper)
        self.assertIn('double(positions[i].x) - double(previous[i].x)', helper)
        self.assertLess(cpp.index('contacts.push_back(contact);\n\t\t\t++hits;'),
                        cpp.index('physics_softbody_solve_pair_edge_contact('))
        self.assertIn('xpbd_pair_edge_tree.clear();\n\txpbd_pair_edges.reset();', cpp)


if __name__ == "__main__":
    unittest.main()
