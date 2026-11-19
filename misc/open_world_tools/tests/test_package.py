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

    def test_invalid_brush_modes_are_rejected_before_iteration(self):
        code = self.terrain.split('func apply_brush(', 1)[1]
        self.assertLess(code.index('mode < BrushMode.RAISE'), code.index('for z in range('))
        self.assertLess(code.index('layer_index < 0 or layer_index > 3'), code.index('for z in range('))

    def test_streaming_zero_size_cell_is_guarded(self):
        code = self.streamer.split('func update_streaming()', 1)[1]
        self.assertLess(code.index('cell_size <= 0.0'), code.index('local_focus.x / cell_size'))
        self.assertIn('is_instance_valid(focus)', code)

    def test_foliage_rejects_invalid_dependencies(self):
        self.assertIn('if terrain == null or foliage_mesh == null:', self.foliage)
        self.assertIn('multimesh = null', self.foliage)
        self.assertIn('return 0', self.foliage)

    def test_sampling_handles_noninteger_coordinates(self):
        self.assertIn('var grid_x: float = clampf(', self.terrain)
        self.assertIn('var grid_z: float = clampf(', self.terrain)
        self.assertIn('var x1: int = mini(x0 + 1, resolution - 1)', self.terrain)
        self.assertIn('var z1: int = mini(z0 + 1, resolution - 1)', self.terrain)

    def test_storage_repair_is_bounded(self):
        self.assertIn('resolution = clampi(resolution, 3, 513)', self.terrain)
        self.assertIn('cell_size = maxf(cell_size, 0.01)', self.terrain)
        self.assertIn('chunk_cells = clampi(chunk_cells, 2, 128)', self.terrain)
        for name in ('height_data', 'color_data', 'weight_data'):
            self.assertIn(f'if {name}.size() != needed:', self.terrain)

    def test_smooth_uses_pre_stroke_snapshot(self):
        self.assertIn('var previous: PackedFloat32Array = height_data.duplicate()', self.terrain)
        self.assertIn('total += previous[sample_index(nx, nz)]', self.terrain)
        self.assertIn('lerpf(previous[index], total / float(count)', self.terrain)

    def test_brush_radius_is_bounded_in_grid_coordinates(self):
        self.assertIn('var left: int = maxi(0, floori(center_x - steps))', self.terrain)
        self.assertIn('var right: int = mini(resolution - 1, ceili(center_x + steps))', self.terrain)
        self.assertIn('var top: int = maxi(0, floori(center_z - steps))', self.terrain)
        self.assertIn('var bottom: int = mini(resolution - 1, ceili(center_z + steps))', self.terrain)

    def test_streaming_duplicate_grid_prevention(self):
        self.assertIn('wanted[key] = true', self.streamer)
        self.assertIn('if _loaded.has(key):', self.streamer)
        self.assertIn('if not wanted.has(key):', self.streamer)

    def test_foliage_placement_attempts_bounded(self):
        self.assertIn('for attempt in range(12):', self.foliage)
        self.assertIn('slope_threshold: float = cos(', self.foliage)
        self.assertIn('terrain.get_normal_at(x, z).dot(Vector3.UP)', self.foliage)

    def test_heightmap_invalid_inputs_are_rejected(self):
        self.assertIn('if image == null or image.is_empty() or max_height < 0.0:', self.terrain)
        self.assertIn('image.get_pixel(image_x, image_y).get_luminance()', self.terrain)

    def test_collision_only_uses_static_shape(self):
        self.assertIn('var body: StaticBody3D = StaticBody3D.new()', self.terrain)
        self.assertIn('shape.shape = mesh.create_trimesh_shape()', self.terrain)
        self.assertNotIn('RigidBody3D.new()', self.terrain)

    def test_runtime_tests_include_edge_cases(self):
        names = [
            '_test_storage_and_mesh_invariants', '_test_invalid_brush_and_snapshots',
            '_test_erosion_extremes', '_test_foliage_world_space_and_slope',
            '_test_streamer_boundaries',
        ]
        for name in names:
            self.assertIn(f'func {name}()', self.godot_tests)
            self.assertIn(f'\t{name}()', self.godot_tests)
        self.assertGreaterEqual(self.godot_tests.count('_check('), 120)

    def test_brush_invalid_input_does_not_commit_undo(self):
        code = self.plugin.split('func _finish_stroke()', 1)[1]
        self.assertIn('if not _stroke_changed or not is_instance_valid(_selected):', code)

    def test_runtime_suite_exits_nonzero_on_failure(self):
        self.assertIn('quit(0 if failures == 0 else 1)', self.godot_tests)
        self.assertIn('push_error("TEST FAILED: " + message)', self.godot_tests)

    def test_no_remote_code_execution_in_addon(self):
        for path in ADDON.glob('*.gd'):
            source = path.read_text()
            for forbidden in ('OS.execute(', 'Expression.execute(', 'HTTPRequest.new(', 'JavaScriptBridge.'):
                self.assertNotIn(forbidden, source, f'{path}: {forbidden}')


if __name__ == '__main__':
    unittest.main()