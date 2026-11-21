"""Static guards for Cgame's batched Camera3D projection and Albion grass LOD.

The native engine and headless game suites must still execute in GitHub CI.
"""
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "scene/3d"
GAME = ROOT / "game/scripts/client"
TESTS = ROOT / "game/tests"


class TestCameraBulkScreenLODContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.header = (SCENE / "camera_3d.h").read_text()
        cls.native = (SCENE / "camera_3d.cpp").read_text()
        cls.chunk = (GAME / "chunk_view.gd").read_text()
        cls.game_test = (TESTS / "test_camera_pixel_density.gd").read_text()
        cls.native_test = (ROOT / "tests/scene/test_camera_3d.cpp").read_text()

    def test_registered_engine_api_and_bounded_batch(self):
        self.assertIn("PackedFloat64Array get_pixels_per_meter_at_positions(", self.header)
        self.assertIn('D_METHOD("get_pixels_per_meter_at_positions", "world_points")', self.native)
        impl = self.native.split(
            "PackedFloat64Array Camera3D::get_pixels_per_meter_at_positions(", 1
        )[1].split("real_t Camera3D::get_world_size_for_pixel_diameter_at_position(", 1)[0]
        self.assertIn("count > 4096", impl)
        self.assertIn("!is_inside_tree()", impl)
        self.assertIn("p_world_positions[i].is_finite()", impl)
        self.assertIn("if (count == 0)", impl)
        self.assertIn("result.resize(count)", impl)
        self.assertIn("result.ptrw()", impl)
        self.assertLess(impl.index("p_world_positions[i].is_finite()"), impl.index("result.resize(count)"))

    def test_shared_projection_and_scalar_semantics(self):
        impl = self.native.split(
            "PackedFloat64Array Camera3D::get_pixels_per_meter_at_positions(", 1
        )[1].split("real_t Camera3D::get_world_size_for_pixel_diameter_at_position(", 1)[0]
        for phrase in (
            "const Projection projection = get_camera_projection();",
            "projection.columns[1][1]",
            "viewport_size.y * 0.5",
            "mode == PROJECTION_ORTHOGONAL",
            "get_camera_transform().affine_inverse()",
            "const real_t depth = -camera_space.z;",
            "depth > CMP_EPSILON",
            "double(focal_y_pixels / depth) : 0.0",
        ):
            self.assertIn(phrase, impl)
        # The expensive camera state is looked up once per group, outside the loop.
        loop = impl.split("for (int i = 0; i < count; ++i) {", 2)[-1]
        self.assertNotIn("get_camera_projection()", loop)
        self.assertNotIn("get_camera_transform()", loop)
        self.assertNotIn("RenderingServer::", impl)
        self.assertNotIn("PhysicsServer", impl)

    def test_live_grass_uses_native_batch_only_after_refresh_gate(self):
        fn = self.chunk.split("func _update_grass_lods() -> void:", 1)[1].split(
            "func _build_npcs(", 1
        )[0]
        self.assertIn("GrassField.needs_lod_refresh(", fn)
        self.assertIn("get_pixels_per_meter_at_positions", fn)
        self.assertIn("view_camera.has_method(\"get_pixels_per_meter_at_positions\")", fn)
        self.assertIn("view_camera.call(\"get_pixels_per_meter_at_positions\", tile_centers)", fn)
        self.assertIn("_grass_tiles.size() <= 4096", fn)
        self.assertIn("batch_density.size() == _grass_tiles.size()", fn)
        self.assertLess(fn.index("GrassField.needs_lod_refresh("), fn.index("tile_centers.append("))
        self.assertIn('view_camera.call("get_pixels_per_meter_at_position", tile_center)', fn)
        self.assertIn("GrassField.projected_lod_distance(", fn)
        self.assertIn("GrassField.lod_for_distance(", fn)
        self.assertIn("GrassField.visible_count_for_distance(", fn)
        self.assertIn("tile.multimesh.mesh = GrassField.clump_mesh(", fn)
        self.assertIn("current", self.chunk)  # The rest of the chunk update survives untouched.

    def test_engine_and_game_parity_tests(self):
        for phrase in (
            "Batched pixels-per-meter matches scalar projection in all modes",
            "Batched screen-space LOD validates whole point set before allocation",
            "get_pixels_per_meter_at_position(points[i])",
            "set_keep_aspect_mode(Camera3D::KEEP_WIDTH)",
            "set_orthogonal(20.0",
            "set_frustum(20.0",
            "points.push_back(Vector3(0, 0, -10))",
            "Vector3(Math::NaN",
            "4096",
        ):
            self.assertIn(phrase, self.native_test)
        for phrase in (
            "real streamed grass batches all tile centers",
            "native orthographic batch equals scalar camera projection",
            "native perspective batch equals scalar camera projection",
            "over 4096 points reject the entire native batch",
            "nonfinite late tile rejects the entire native batch",
        ):
            self.assertIn(phrase, self.game_test)

    def test_documentation_and_native_ci(self):
        doc = ET.parse(ROOT / "doc/classes/Camera3D.xml").getroot()
        names = {m.get("name") for m in doc.findall("./methods/method")}
        self.assertIn("get_pixels_per_meter_at_positions", names)
        notes = (ROOT / "game/docs/camera_bulk_screen_lod.md").read_text()
        self.assertIn("4096", notes)
        self.assertIn("Unreal", notes)
        workflow = (ROOT / ".github/workflows/native-camera-bulk-screen-lod.yml").read_text()
        for phrase in (
            "test_camera_bulk_screen_lod_contract.py",
            'test_camera_3d.cpp',
            '--test-case="*Batched*"',
            "run_one.gd -- test_camera_pixel_density test_grass_lod",
            "TOTAL [0-9]+ checks, 0 failures",
        ):
            self.assertIn(phrase, workflow)


if __name__ == "__main__":
    unittest.main()
