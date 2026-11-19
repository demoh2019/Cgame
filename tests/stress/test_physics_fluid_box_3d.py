"""Source contracts and independent statistical reference for oriented-box buoyancy.

Uses Python's standard library only. Native GodotPhysics C++/GDScript tests
must additionally run on the actual engine.
"""
from pathlib import Path
import math
import random
import unittest

ROOT = Path(__file__).resolve().parents[2]
BOX = ROOT / "servers/physics_fluid_box_3d.h"
BODY = ROOT / "modules/godot_physics_3d/godot_body_3d.cpp"
NATIVE = ROOT / "tests/servers/test_physics_fluid_box_3d.cpp"
HEADLESS = ROOT / "tests/stress/physics_fluid_oriented_box_3d_regression.gd"


def cross(a, b):
    return (a[1]*b[2]-a[2]*b[1],
            a[2]*b[0]-a[0]*b[2],
            a[0]*b[1]-a[1]*b[0])


def dot(a, b):
    return sum(x*y for x, y in zip(a, b))


def volume_tetra(a, b, c, d):
    return abs(dot(tuple(b[i]-a[i] for i in range(3)),
                   cross(tuple(c[i]-a[i] for i in range(3)),
                         tuple(d[i]-a[i] for i in range(3))))) / 6


CUBE = [(-1, -1, -1), (1, -1, -1), (-1, 1, -1), (1, 1, -1),
        (-1, -1, 1), (1, -1, 1), (-1, 1, 1), (1, 1, 1)]
TETS = [(0, 1, 3, 7), (0, 1, 5, 7), (0, 2, 3, 7),
        (0, 2, 6, 7), (0, 4, 5, 7), (0, 4, 6, 7)]


def monte_carlo_box_fraction_and_centroid(half, y_coefficients, center_y,
                                           surface, seed, count=20000):
    """Uniformly sample the actual tilted/sheared solid, not its world AABB."""
    rng = random.Random(seed)
    count_wet = 0
    moment = 0.0
    for _ in range(count):
        x = rng.uniform(-half[0], half[0])
        y = rng.uniform(-half[1], half[1])
        z = rng.uniform(-half[2], half[2])
        world_y = center_y + y_coefficients[0]*x + y_coefficients[1]*y + y_coefficients[2]*z
        if world_y <= surface:
            count_wet += 1
            moment += world_y
    return count_wet / count, (moment / count_wet if count_wet else None)


class OrientedBoxBuoyancyTests(unittest.TestCase):
    def test_six_tetrahedra_partition_box_without_overlap(self):
        each = [volume_tetra(*(CUBE[i] for i in tet)) for tet in TETS]
        for v in each:
            self.assertAlmostEqual(v, 4 / 3)
        self.assertAlmostEqual(sum(each), 8.0)

    def test_known_rotated_box_centre_differs_from_aabb(self):
        self.assertAlmostEqual(-math.sqrt(2) / 3, -0.4714045207910317)
        self.assertGreater(abs(-math.sqrt(2) / 3 + math.sqrt(2) / 2), 0.23)
        # For the 30-degree tilted body used in the headless regression,
        # a separate uniform-volume Monte Carlo check verifies that the
        # submerged fraction is about 0.12805, not its AABB's 0.29793.
        angle = math.pi / 6
        ratio, center_y = monte_carlo_box_fraction_and_centroid(
            (1, 1, 1), (math.sin(angle), math.cos(angle), 0),
            0.7, 0.0, seed=472, count=90000)
        self.assertAlmostEqual(ratio, 0.12805335632990217, delta=0.006)
        self.assertAlmostEqual(center_y, -0.222008468, delta=0.03)
        self.assertLess(ratio, 0.29792740578363097 / 2)

    def test_random_affine_boxes_are_bounded_and_finite(self):
        rng = random.Random(20261119)
        for i in range(36):
            half = tuple(rng.uniform(0.5, 2.0) for _ in range(3))
            # This covers rotation-like and shear-like world Y rows.
            coefficients = tuple(rng.uniform(-1.5, 1.5) for _ in range(3))
            center = rng.uniform(-0.7, 0.7)
            surface = rng.uniform(-0.4, 0.4)
            fraction, centroid = monte_carlo_box_fraction_and_centroid(
                half, coefficients, center, surface, seed=3000+i, count=2500)
            self.assertLessEqual(0.0, fraction)
            self.assertLessEqual(fraction, 1.0)
            if centroid is not None:
                self.assertTrue(math.isfinite(centroid))
                self.assertLessEqual(centroid, surface + 1e-8)
            if surface > center + sum(abs(a*b) for a,b in zip(half,coefficients)):
                self.assertEqual(fraction, 1.0)
            if surface < center - sum(abs(a*b) for a,b in zip(half,coefficients)):
                self.assertEqual(fraction, 0.0)

    def test_exact_box_buoyancy_is_wired_without_allocations(self):
        helper = BOX.read_text(encoding="utf8")
        body = BODY.read_text(encoding="utf8")
        self.assertIn("godot_physics_fluid_box_sample_3d(", helper)
        self.assertIn("godot_physics_fluid_clip_tetra_3d(", helper)
        self.assertIn("const uint8_t tetrahedra[6][4]", helper)
        self.assertIn("max_distance <= 0.0 || min_distance >= 0.0", helper)
        self.assertIn("submerged.moment_y / submerged.volume", helper)
        self.assertIn("p_transform.basis.determinant()", helper)
        self.assertNotIn("memalloc(", helper)
        self.assertNotIn("resize(", helper)
        self.assertIn("shape_type == PS3DE::SHAPE_BOX", body)
        self.assertIn("box->get_half_extents()", body)
        self.assertIn("total_fluid_shape_volume += exact_box_volume - shape_volume", body)
        self.assertIn("sample = godot_physics_fluid_sample_3d(bounds, shape_volume, water_height);", body)
        self.assertIn("torque += lever.cross(lift + drag);", body)

    def test_cpp_and_headless_regressions_present(self):
        native = NATIVE.read_text(encoding="utf8")
        gd = HEADLESS.read_text(encoding="utf8")
        self.assertIn("TEST_FORCE_LINK(test_physics_fluid_box_3d)", native)
        self.assertIn("Rotated box hydrostatic centroid differs from naive world AABB", native)
        self.assertIn("supports nonuniform scale reflection shear", native)
        self.assertIn("box_sinks", gd)
        self.assertIn("matching_lift", gd)
        self.assertIn("correct_torque", gd)


if __name__ == "__main__":
    unittest.main()
