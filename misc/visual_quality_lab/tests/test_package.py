"""Lightweight packaging checks; not a substitute for a Godot runtime test."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]


class VisualQualityPackageTests(unittest.TestCase):
    def test_all_scene_references_exist(self):
        scene = (ROOT / 'demo.tscn').read_text()
        scripts = (ROOT / 'demo.gd').read_text()
        for text in (scene, scripts):
            for path in re.findall(r'res://([^"\\s]+)', text):
                self.assertTrue((ROOT / path).is_file(), path)

    def test_sky_shader_never_uses_return_in_sky(self):
        shader = (ROOT / 'addons/visual_quality/filmic_sky.gdshader').read_text()
        self.assertIn('shader_type sky;', shader)
        body = shader.split('void sky()', 1)[1]
        body = re.sub(r'//[^\\n]*', '', body)
        self.assertNotRegex(body, r'\\breturn\\b')
        self.assertNotRegex(body, r'\\bTIME\\b')
        self.assertIn('COLOR =', body)

    def test_scaler_has_fps_smoothing_and_hysteresis(self):
        script = (ROOT / 'addons/visual_quality/adaptive_resolution.gd').read_text()
        for feature in ('_fps_sum', '_samples', 'cooldown_seconds',
                        'low_fps_ratio', 'high_fps_ratio',
                        'restore_on_exit', 'calculate_next_scale'):
            self.assertIn(feature, script)


if __name__ == '__main__':
    unittest.main()
