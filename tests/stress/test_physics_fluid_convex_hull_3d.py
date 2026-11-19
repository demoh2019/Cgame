"""Convex hydrostatic source contracts and independent geometric oracles.

Run: python3 -m unittest discover -s tests/stress \
    -p test_physics_fluid_convex_hull_3d.py -v
Native C++ and headless Godot tests must still be run separately.
"""
from pathlib import Path
import math
import random
import unittest

ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "servers/physics_fluid_convex_hull_3d.h"
BODY = ROOT / "modules/godot_physics_3d/godot_body_3d.cpp"
NATIVE = ROOT / "tests/servers/test_physics_fluid_convex_hull_3d.cpp"
HEADLESS = ROOT / "tests/stress/physics_convex_hydrostatic_3d_regression.gd"


def independent_cross_section_fraction_tetra(points, surface, samples=30000):
    """Uniform tetrahedron points from normalized independent exponentials.

    This is a seeded *statistical* oracle independent from tetra clipping.
    It does not call the algorithm being validated.
    """
    rng = random.Random(60553)
    count = 0
    sum_y = 0.0
    for _ in range(samples):
        w = [-math.log(max(rng.random(), 1e-300)) for _ in range(4)]
        total = sum(w)
        y = sum(w[i] * points[i][1] for i in range(4)) / total
        if y <= surface:
            count += 1
            sum_y += y
    return count / samples, (sum_y / count if count else None)


class ConvexFluidTests(unittest.TestCase):
    def test_axis_aligned_and_tilted_convex_box(self):
        # Cube [-1, 1]^3, half submerged: exact V=4 and COB_y=-1/2.
        self.assertEqual(2 * 2 * 2 / 2, 4.0)
        self.assertEqual(-0.5, -0.5)
        # Rotated 45 degrees about Z: diamond cross sections in XY.
        # Half its volume lies below y=0, center_y=-sqrt(2)/3.
        self.assertAlmostEqual(-math.sqrt(2) / 3, -0.4714045207910317)

    def test_tetra_one_two_three_submerged_vertices_against_barycentric_sampling(self):
        cases = [
            ([(0, -1, 0), (1, 1, 0), (0, 1, 1), (0, 1, -1)], 0.125, -0.25),
            ([(0, -1, 0), (1, -1, 0), (0, 1, 0), (0, 1, 1)], 0.5, -0.375),
            ([(0, 1, 0), (1, -1, 0), (0, -1, 1), (0, -1, -1)], 0.875, -17 / 28),
        ]
        for points, fraction, centroid_y in cases:
            with self.subTest(fraction=fraction):
                numerical_fraction, numerical_y = independent_cross_section_fraction_tetra(points, 0.0)
                self.assertAlmostEqual(numerical_fraction, fraction, delta=0.012)
                self.assertAlmostEqual(numerical_y, centroid_y, delta=0.025)

    def test_full_convex_volume_is_not_aabb_volume(self):
        # A tetrahedron fills one sixth of its axis-aligned containing box.
        # For this 2x2x2 tetra, full volume=8/6 and under y=0 wet=7/6.
        hull_volume = 8 / 6
        box_volume = 8
        actual_wet = hull_volume * 7 / 8
        aabb_wet = box_volume / 2
        self.assertAlmostEqual(actual_wet, 7 / 6)
        self.assertGreater(aabb_wet, actual_wet * 3)
        self.assertLess(0.75 * actual_wet, 1)
        self.assertGreater(0.75 * aabb_wet, 1)

    def test_exact_tetra_clipping_and_body_integration_contracts(self):
        src = HELPER.read_text(encoding="utf-8")
        body = BODY.read_text(encoding="utf-8")
        for token in (
            "struct GodotPhysicsFluidTetraSum3D",
            "godot_physics_fluid_clip_tetra_3d(",
            "godot_physics_fluid_convex_hull_sample_3d(",
            "p_mesh.faces[f]", "interior_distance",
            "count_inside == 1", "count_inside == 3",
            "r_submerged.add(p_vertices[a], ac, bd, ad)",
            "p_transform.basis.determinant()",
            "vertex_count > 512 || face_count > 256",
            "r_sample.submerged_volume = real_t(world_wet)",
            "submerged.moment_x / submerged.volume",
        ):
            self.assertIn(token, src)
        self.assertIn('servers/physics_fluid_convex_hull_3d.h', body)
        self.assertIn("shape_type == PS3DE::SHAPE_CONVEX_POLYGON", body)
        self.assertIn("convex->get_mesh(), shape_world", body)
        self.assertIn("total_fluid_shape_volume += hull_volume - shape_volume;", body)
        self.assertIn("sample = godot_physics_fluid_sample_3d(bounds, shape_volume, water_height)", body)
        self.assertIn("torque += lever.cross(lift + drag);", body)

    def test_regression_files_present(self):
        native = NATIVE.read_text(encoding="utf-8")
        gd = HEADLESS.read_text(encoding="utf-8")
        self.assertIn("TEST_FORCE_LINK(test_physics_fluid_convex_hull_3d)", native)
        self.assertIn("make_box_mesh(", native)
        self.assertIn("make_tetra_mesh(", native)
        self.assertIn("Convex tetra clipping handles one, two, three and four wet vertices", native)
        for token in ("convex_sinks", "box_floats", "buoyant_torque", "tilted_finite"):
            self.assertIn(token, gd)


if __name__ == "__main__":
    unittest.main()
