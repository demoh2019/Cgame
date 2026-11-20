"""Packaging and configuration invariants; runtime coverage requires Godot."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]


class VisualQualityPackageTests(unittest.TestCase):
    def test_all_script_references_exist(self):
        files = [ROOT / 'demo.tscn', ROOT / 'demo.gd']
        files += sorted((ROOT / 'addons').rglob('*.gd'))
        files += sorted((ROOT / 'tests').glob('*.gd'))
        for file in files:
            for path in re.findall(r'res://([^"\s]+)', file.read_text()):
                self.assertTrue((ROOT / path).is_file(), f'{file.name} -> {path}')

    def test_sky_shader_no_invalid_return(self):
        shader = (ROOT / 'addons/visual_quality/filmic_sky.gdshader').read_text()
        self.assertIn('shader_type sky;', shader)
        body = shader.split('void sky()', 1)[1]
        body = re.sub(r'//[^\n]*', '', body)
        self.assertNotRegex(body, r'\breturn\b')
        self.assertNotRegex(body, r'\bTIME\b')
        self.assertIn('AT_CUBEMAP_PASS', body)
        self.assertIn('COLOR =', body)

    def test_scaler_has_cpu_guard_hysteresis_and_restoration(self):
        script = (ROOT / 'addons/visual_quality/adaptive_resolution.gd').read_text()
        for feature in ('_fps_sum', '_samples', 'cooldown_seconds', 'low_fps_ratio',
                        'high_fps_ratio', 'restore_on_exit', 'calculate_next_scale',
                        'Performance.TIME_PROCESS', 'Performance.TIME_PHYSICS_PROCESS',
                        'is_cpu_bound', 'skip_cpu_bound_drops',
                        'viewport_set_measure_render_time',
                        'viewport_get_measured_render_time_gpu',
                        'calculate_next_scale_from_gpu', 'gpu_headroom_ratio'):
            self.assertIn(feature, script)

    def test_quality_manager_persists_only_opt_in_project_preferences(self):
        script = (ROOT / 'addons/visual_quality/quality_manager.gd').read_text()
        self.assertIn('user://visual_quality_lab.cfg', script)
        for section in ('validated_profile', 'ConfigFile.new()', 'file.load',
                        'file.save', 'restore_environment_on_exit',
                        'ssao_enabled', 'ssil_enabled', 'ssr_enabled',
                        'Sky.RADIANCE_SIZE_128', 'Sky.RADIANCE_SIZE_256',
                        'use_512_radiance_in_cinematic', '_old_radiance_size'):
            self.assertIn(section, script)
        self.assertNotIn('ProjectSettings.set_setting', script)

    def test_demo_has_accessible_clickable_settings(self):
        demo = (ROOT / 'demo.gd').read_text()
        self.assertIn('HBoxContainer.new()', demo)
        self.assertIn('Button.new()', demo)
        self.assertIn('settings_changed.connect', demo)
        self.assertIn('set_adaptive_enabled', demo)
        self.assertIn('set_profile', demo)

    def test_atmosphere_is_budgeted_and_has_restoration(self):
        source = (ROOT / 'addons/visual_quality/atmosphere_controller.gd').read_text()
        for feature in ('sunlight_factor', 'fog_density_for', 'update_interval_seconds',
                        '_saved_shader_uniforms', '_exit_tree', 'atmosphere_changed',
                        'maxf(update_interval_seconds, 0.25)', 'set_overcast',
                        'sun.light_energy', 'environment.fog_density'):
            self.assertIn(feature, source)

    def test_visual_sky_supports_night_but_no_per_frame_time(self):
        shader = (ROOT / 'addons/visual_quality/filmic_sky.gdshader').read_text()
        for parameter in ('night_amount', 'night_color', 'stars_intensity',
                          'AT_CUBEMAP_PASS', 'RADIANCE'):
            self.assertIn(parameter, shader)
        self.assertNotRegex(re.sub(r'//[^\n]*', '', shader), r'\bTIME\b')

    def test_demo_exposes_weather_and_day_night(self):
        source = (ROOT / 'demo.gd').read_text()
        self.assertIn('atmosphere.atmosphere_changed.connect', source)
        self.assertIn('_toggle_weather()', source)
        self.assertIn('_toggle_hour()', source)
        self.assertIn('_toggle_cycle()', source)

    def test_headless_regression_suites_present(self):
        for filename in ('test_adaptive_resolution.gd', 'test_quality_manager.gd', 'test_atmosphere.gd'):
            text = (ROOT / 'tests' / filename).read_text()
            self.assertIn('extends SceneTree', text)
            self.assertIn('assert(', text)
            self.assertIn('quit(0)', text)


if __name__ == '__main__':
    unittest.main()
