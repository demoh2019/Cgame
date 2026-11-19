"""Offline source-contract checks. Real GDScript execution is in test_world_tools.gd."""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ADDON = ROOT / "addons" / "open_world_tools"


class PackageContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.terrain = (ADDON / "world_terrain_3d.gd").read_text()
        cls.plugin = (ADDON / "plugin.gd").read_text()
        cls.streamer = (ADDON / "world_streamer_3d.gd").read_text()
        cls.foliage = (ADDON / "world_foliage_3d.gd").read_text()
        cls.shader = (ADDON / "terrain_splat.gdshader").read_text()
        cls.godot_tests = (ROOT / "tests" / "test_world_tools.gd").read_text()

    def test_plugin_manifest(self):
        data = (ADDON / "plugin.cfg").read_text()
        self.assertIn('[plugin]', data)
        self.assertIn('script="plugin.gd"', data)

    def test_project_entrypoint(self):
        project = (ROOT / "project.godot").read_text()
        self.assertIn('res://demo.tscn', project)
        self.assertTrue((ROOT / "demo.tscn").is_file())

    def test_all_res_paths_resolve(self):
        for path in ROOT.rglob("*.gd"):
            data = path.read_text()
            for res in re.findall(r'res://([^"\'\s]+)', data):
                self.assertTrue((ROOT / res).exists(), f"missing {res} from {path}")
        self.assertTrue((ADDON / "terrain_splat.gdshader").exists())

    def test_no_conflicting_global_classes(self):
        classes = []
        for path in ADDON.glob("*.gd"):
            classes += re.findall(r"(?m)^class_name\s+(\w+)", path.read_text())
        self.assertEqual(len(classes), 4)
        self.assertEqual(len(classes), len(set(classes)))

    def test_heightfield_grid_bounds(self):
        self.assertIn("resolution * resolution", self.terrain)
        self.assertIn("z * resolution + x", self.terrain)
        self.assertIn("contains_xz", self.terrain)
        self.assertIn("lerpf(a, b", self.terrain)

    def test_brushes_include_undo_snapshots(self):
        for mode in ["RAISE", "SMOOTH", "FLATTEN", "PAINT", "PAINT_TEXTURE_LAYER"]:
            self.assertIn(mode, self.terrain)
        self.assertIn('restore_samples', self.plugin)
        self.assertIn('add_do_method', self.plugin)
        self.assertIn('add_undo_method', self.plugin)
        self.assertIn('commit_action(false)', self.plugin)

    def test_height_storage_persisted(self):
        for name in ['height_data', 'color_data', 'weight_data']:
            self.assertRegex(self.terrain, r'@export_storage var ' + name + r': Packed')

    def test_foliage_deterministic(self):
        self.assertIn('rng.seed = random_seed', self.foliage)
        self.assertIn('max_slope_degrees', self.foliage)
        self.assertIn('MultiMesh.TRANSFORM_3D', self.foliage)
        self.assertIn('get_height_at', self.foliage)
        self.assertIn('global_transform.affine_inverse()', self.foliage)

    def test_erosion_uses_balanced_deltas(self):
        self.assertIn('deltas[a] -= flow', self.terrain)
        self.assertIn('deltas[b] += flow', self.terrain)
        self.assertIn('rate = clampf(rate, 0.0, 1.0)', self.terrain)

    def test_splat_layers_defined(self):
        for i in range(4):
            self.assertIn(f'uniform sampler2D layer_{i}', self.shader)
            self.assertIn(f'material.set_shader_parameter("layer_%d" % i', self.terrain)
        self.assertIn('dot(weights, vec4(1.0))', self.shader)
        self.assertIn('weights / total', self.shader)

    def test_streaming_handles_negative_coords(self):
        self.assertIn('floori(local_focus.x / cell_size)', self.streamer)
        self.assertIn('floori(local_focus.z / cell_size)', self.streamer)
        self.assertIn('old.queue_free()', self.streamer)
        self.assertIn('get_loaded_cell_count', self.streamer)

    def test_collision_is_optional(self):
        self.assertIn('enable_collision: bool = false', self.terrain)
        self.assertIn('mesh.create_trimesh_shape()', self.terrain)

    def test_godot_regressions_cover_all_modules(self):
        for part in ['_test_heightmap()', '_test_brushes()', '_test_erosion()', '_test_foliage()', '_test_streamer()']:
            self.assertIn(part, self.godot_tests)
        self.assertGreaterEqual(self.godot_tests.count('_check('), 55)

    def test_user_scope_documented(self):
        for filename in ('README.md', 'ROADMAP.md'):
            self.assertTrue((ROOT / filename).is_file())
        self.assertEqual(len(re.findall(r'^\|\s*\d+\s*\|', (ROOT / 'ROADMAP.md').read_text(), re.M)), 48)

    def test_no_engine_core_changes(self):
        self.assertFalse((ROOT / '.sconsign.dblite').exists())
        self.assertFalse((ROOT / 'modules').exists())


if __name__ == '__main__':
    unittest.main()