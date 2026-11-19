"""Reference and source integration checks for FEM volume-lumped nodal mass.

Run: python3 -m unittest discover -s tests/stress -p test_physics_fem_lumped_mass.py -v

The numerical reference uses Python doubles. It verifies mass fractions
and invariants, not a complete GodotPhysics3D build or FEM solver run.
"""
import math
from pathlib import Path
import random
import unittest

ROOT = Path(__file__).resolve().parents[2]


def lump(count, tets, total_mass):
    if not (4 <= count <= 2048 and tets and
            math.isfinite(total_mass) and total_mass > 0):
        return None
    mass = [0.0] * count
    volume = 0.0
    for vertices, tet_volume in tets:
        if (len(vertices) != 4 or len(set(vertices)) != 4 or
                any(i < 0 or i >= count for i in vertices) or
                not math.isfinite(tet_volume) or not tet_volume > 0):
            return None
        volume += tet_volume
        if not math.isfinite(volume):
            return None
        for i in vertices:
            mass[i] += tet_volume / 4
    if volume <= 0:
        return None
    fractions = [m / volume for m in mass]
    if not all(math.isfinite(f) and f > 0 for f in fractions):
        return None
    if abs(sum(fractions) - 1.0) > 1e-8:
        return None
    inverse_masses = [1 / (total_mass * f) for f in fractions]
    if not all(math.isfinite(im) and im > 0 for im in inverse_masses):
        return None
    return fractions, inverse_masses


class FEMLumpedMassContracts(unittest.TestCase):
    def test_two_tetrahedra_have_nonuniform_vertex_mass(self):
        weights, inverse = lump(
            5, [((0, 1, 2, 3), 1), ((0, 2, 3, 4), 3)], 8)
        expected = [0.25, 0.0625, 0.25, 0.25, 0.1875]
        self.assertEqual(weights, expected)
        for i in range(5):
            self.assertAlmostEqual(inverse[i], 1 / (8 * expected[i]))
        self.assertAlmostEqual(sum(1 / im for im in inverse), 8)

    def test_tetra_shape_scale_does_not_change_mass_ratios(self):
        for scale in (1e-24, 1e-12, 1, 1e15, 1e60):
            result = lump(5, [((0, 1, 2, 3), scale),
                              ((0, 2, 3, 4), 3 * scale)], 8)
            self.assertIsNotNone(result)
            self.assertEqual(result[0], [0.25, 0.0625, 0.25, 0.25, 0.1875])

    def test_randomized_6000_connected_tetra_material_masses(self):
        rng = random.Random(20261119)
        for _ in range(6000):
            count = rng.randint(4, 90)
            scale = 10 ** rng.uniform(-25, 60)
            tets = []
            # Each new vertex appears in at least one tetrahedron.
            for i in range(4, count):
                tets.append(((0, 1, 2, i), scale * rng.uniform(.05, 3.0)))
            tets.append(((0, 1, 2, 3), scale * rng.uniform(.05, 3.0)))
            mass = 10 ** rng.uniform(-4, 4)
            weights, inverse = lump(count, tets, mass)
            self.assertTrue(all(math.isfinite(x) and x > 0 for x in inverse))
            self.assertAlmostEqual(sum(weights), 1.0, places=12)
            self.assertAlmostEqual(sum(1.0 / im for im in inverse),
                                   mass, delta=mass * 1e-12)

    def test_pins_keep_mass_fraction_and_unpin_restores(self):
        result = lump(5, [((0, 1, 2, 3), 1), ((0, 2, 3, 4), 3)], 8)
        fractions, inverse = result
        pinned = list(inverse)
        pinned[4] = 0.0
        self.assertEqual(pinned[4], 0)
        self.assertAlmostEqual(1 / (8 * fractions[4]), inverse[4])
        self.assertAlmostEqual(1 / (16 * fractions[4]), inverse[4] / 2)

    def test_invalid_topology_and_inputs_have_no_output(self):
        self.assertIsNone(lump(5, [((0, 1, 2, 3), 1)], 8))
        self.assertIsNone(lump(4, [((0, 1, 1, 3), 1)], 8))
        self.assertIsNone(lump(4, [((0, 1, 2, 4), 1)], 8))
        self.assertIsNone(lump(4, [((0, 1, 2, 3), 0)], 8))
        self.assertIsNone(lump(4, [((0, 1, 2, 3), math.inf)], 8))
        self.assertIsNone(lump(4, [((0, 1, 2, 3), 1)], 0))

    def test_source_cooker_and_pin_unpin_integration(self):
        helper = (ROOT / "servers/physics_fem_lumped_mass.h").read_text()
        body = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.cpp").read_text()
        header = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.h").read_text()
        settings = (ROOT / "servers/physics_3d/physics_server_3d.cpp").read_text()
        space = (ROOT / "modules/godot_physics_3d/godot_space_3d.cpp").read_text()
        self.assertIn("volume * 0.25", helper)
        self.assertIn("r_fractions = std::move(fractions);", helper)
        self.assertIn("r_inverse_masses = std::move(inverse_masses);", helper)
        self.assertIn("physics_fem_build_lumped_masses(", body)
        self.assertIn("physics_fem_unpinned_inverse_mass(", body)
        self.assertIn("get_unpinned_node_inverse_mass(node_index)", body)
        self.assertIn("LocalVector<double> xpbd_fem_mass_fractions;", header)
        self.assertIn("get_soft_body_tetra_fiber_compliance() <= 0.0 &&", body)
        self.assertIn('GLOBAL_GET("physics/3d/solver/soft_body_tetra_fem_lumped_mass")', space)
        self.assertIn('"physics/3d/solver/soft_body_tetra_fem_lumped_mass"), false', settings)

    def test_off_by_default_and_normal_fallback(self):
        body = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.cpp").read_text()
        self.assertIn("if (previously_lumped)", body)
        self.assertIn("node.im = uniform_inverse;", body)
        self.assertIn("if (nodes[i].im > 0.0)", body)
        self.assertIn("link_constants_dirty = true;", body)


if __name__ == "__main__":
    unittest.main()
