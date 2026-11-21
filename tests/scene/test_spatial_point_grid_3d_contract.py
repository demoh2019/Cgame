"""Static contracts and reference numeric model for Cgame's 3D spatial index.

This cannot substitute for native compilation and the Godot headless suite.
"""
import math
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
NATIVE = ROOT / "scene/main"
GAME = ROOT / "game"


def count3d(points, center, radius, limit=20):
    if radius < 0 or not math.isfinite(radius) or not all(map(math.isfinite, center)):
        return -1
    return min(limit, sum(
        (x - center[0]) ** 2 + (y - center[1]) ** 2 + (z - center[2]) ** 2 <= radius * radius
        for x, y, z in points if all(map(math.isfinite, (x, y, z)))
    ))


class Spatial3DContracts(unittest.TestCase):
    def test_new_native_class_registered_with_safe_buckets(self):
        reg = (ROOT / "scene/register_scene_types.cpp").read_text()
        header = (NATIVE / "spatial_point_grid_3d.h").read_text()
        code = (NATIVE / "spatial_point_grid_3d.cpp").read_text()
        xml = ET.parse(ROOT / "doc/classes/SpatialPointGrid3D.xml").getroot()
        self.assertIn("GDREGISTER_CLASS(SpatialPointGrid3D)", reg)
        self.assertIn("HashMap<Vector3i, Vector<Vector3>> cells", header)
        self.assertIn("bool rebuild(const TypedArray<Vector3>", header)
        self.assertIn("int count_within(const Vector3", header)
        self.assertIn("count_within_batch(const PackedVector3Array", header)
        self.assertIn("MAX_BUCKET_VISITS = 4096", header)
        self.assertIn("p_center.distance_squared_to(point)", code)
        self.assertIn("nx * ny * nz > MAX_BUCKET_VISITS", code)
        self.assertIn("return -1;", code)
        self.assertIn("if (p_positions.size() > MAX_POINTS)", code)
        self.assertIn("D_METHOD(\"count_within\"", code)
        self.assertEqual(xml.attrib["name"], "SpatialPointGrid3D")

    def test_live_game_consumes_authoritative_3d_index(self):
        director = (GAME / "scripts/shared/world_encounter_director.gd").read_text()
        server = (GAME / "scripts/server/game_server.gd").read_text()
        suite = (GAME / "tests/test_world_encounter_director.gd").read_text()
        self.assertIn('ClassDB.class_exists("SpatialPointGrid3D")', director)
        self.assertIn('native.call("count_within", center,', director)
        self.assertIn("prefer_native: bool = true", director)
        self.assertIn("center.distance_squared_to(position)", director)
        self.assertIn("WorldEncounterDirector.nearby_infected(", server)
        self.assertIn("game fallback at probe", suite)
        self.assertIn("native 3D index accepts finite volumetric points", suite)

    def test_exact_boundary_and_vertical_separation(self):
        p = [(0, 0, 0), (0, 75, 0), (0, -75, 0), (0, 76, 0), (0, 0, 75)]
        self.assertEqual(count3d(p, (0, 0, 0), 75), 4)
        self.assertEqual(count3d(p, (0, 0, 0), 75, 2), 2)
        self.assertEqual(count3d(p, (0, 1000, 0), 75), 0)
        self.assertEqual(count3d(p, (0, 0, 0), 0), 1)
        self.assertEqual(count3d(p, (0, 0, 0), -1), -1)
        self.assertEqual(count3d(p, (math.nan, 0, 0), 75), -1)
        self.assertEqual(count3d(p, (0, 0, 0), math.inf), -1)


if __name__ == "__main__":
    unittest.main()
