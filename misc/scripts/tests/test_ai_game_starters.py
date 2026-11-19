"""Regression tests for offline AI Game Builder starter projects."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import ai_game_starters as starters


class StarterTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.base = Path(temporary.name)
        self.dest = self.base / 'starter'

    def cli(self, *args):
        return subprocess.run([sys.executable, starters.__file__, '--output', str(self.dest), *args],
                              capture_output=True, text=True)

    def test_all_three_templates_available(self):
        self.assertEqual(starters.TEMPLATES, ('platformer', 'topdown', 'fps3d'))

    def test_all_templates_have_same_artifact_set(self):
        for template in starters.TEMPLATES:
            with self.subTest(template=template):
                self.assertEqual(set(starters.files_for(template, 'Test')),
                                 {'project.godot', 'main.tscn', 'game.gd', 'README.md', 'ai_recipe.json'})

    def test_template_names_rejected_if_unknown(self):
        for value in ('', 'Platformer', 'unity', '../platformer', None):
            with self.subTest(value=value), self.assertRaises(starters.StarterError):
                starters.files_for(value, 'Game')

    def test_scripts_are_nonempty_and_extend_correct_node(self):
        for template in starters.TEMPLATES:
            script = starters.files_for(template, 'Demo')['game.gd']
            node = 'Node3D' if template == 'fps3d' else 'Node2D'
            self.assertTrue(script.startswith('extends ' + node + '\n'))
            self.assertIn('func _ready() -> void:', script)
            self.assertIn('func _physics_process(', script)

    def test_scene_references_script(self):
        for template in starters.TEMPLATES:
            scene = starters.files_for(template, 'Demo')['main.tscn']
            self.assertIn('path="res://game.gd"', scene)
            self.assertIn('script = ExtResource("1")', scene)
            self.assertIn('type="Node3D"' if template == 'fps3d' else 'type="Node2D"', scene)

    def test_every_template_has_main_scene_project_setting(self):
        for template in starters.TEMPLATES:
            cfg = starters.files_for(template, 'Demo')['project.godot']
            self.assertIn('config_version=5', cfg)
            self.assertIn('run/main_scene="res://main.tscn"', cfg)
            self.assertIn('renderer/rendering_method=', cfg)

    def test_project_name_escaped(self):
        cfg = starters.files_for('topdown', 'Game "x" \\ snow')['project.godot']
        self.assertIn('config/name="Game \\"x\\" \\\\ snow"', cfg)

    def test_cyrillic_project_name_supported(self):
        cfg = starters.files_for('fps3d', 'Лесной мир')['project.godot']
        self.assertIn('config/name="Лесной мир"', cfg)

    def test_newline_control_names_rejected(self):
        for name in ('a\nb', 'a\rb', 'a\x00b', 'a\x7fb', '', 'x' * 81):
            with self.subTest(name=repr(name)), self.assertRaises(starters.StarterError):
                starters.files_for('platformer', name)

    def test_longest_allowed_name(self):
        cfg = starters.files_for('topdown', 'x' * 80)['project.godot']
        self.assertIn('x' * 80, cfg)

    def test_recipe_contains_template_and_controls(self):
        for template in starters.TEMPLATES:
            files = starters.files_for(template, 'Demo')
            recipe = json.loads(files['ai_recipe.json'])
            self.assertEqual(recipe['schema_version'], 1)
            self.assertEqual(recipe['template'], template)
            self.assertEqual(recipe['controls'], starters.CONTROLS[template])
            self.assertEqual(recipe['editable_files'], ['main.tscn', 'game.gd'])

    def test_sha256_checksums_match_exact_source_bytes(self):
        for template in starters.TEMPLATES:
            files = starters.files_for(template, 'Test')
            recipe = json.loads(files['ai_recipe.json'])
            for path, checksum in recipe['sha256'].items():
                with self.subTest(template=template, file=path):
                    self.assertEqual(hashlib.sha256(files[path].encode()).hexdigest(), checksum)

    def test_recipe_does_not_self_hash(self):
        recipe = json.loads(starters.files_for('platformer', 'Test')['ai_recipe.json'])
        self.assertNotIn('ai_recipe.json', recipe['sha256'])

    def test_deterministic_sources(self):
        for template in starters.TEMPLATES:
            self.assertEqual(starters.files_for(template, 'Test'), starters.files_for(template, 'Test'))

    def test_scripts_do_not_load_remote_assets(self):
        for template in starters.TEMPLATES:
            script = starters.files_for(template, 'Test')['game.gd']
            for bad in ('HTTPClient', 'HTTPRequest', 'load("res://', 'preload(', 'OS.execute('):
                with self.subTest(template=template, bad=bad):
                    self.assertNotIn(bad, script)

    def test_no_tool_scripts_or_editor_executed_scripts(self):
        for template in starters.TEMPLATES:
            self.assertNotIn('@tool', starters.files_for(template, 'Test')['game.gd'])

    def test_platformer_has_jump_and_collision(self):
        script = starters.files_for('platformer', 'Test')['game.gd']
        for keyword in ('CharacterBody2D.new()', 'StaticBody2D.new()',
                        'CollisionShape2D.new()', 'JUMP_SPEED', 'move_and_slide()'):
            self.assertIn(keyword, script)

    def test_topdown_collectibles_and_walls(self):
        script = starters.files_for('topdown', 'Test')['game.gd']
        for keyword in ('collected', 'pickups', 'CircleShape2D.new()',
                        'StaticBody2D.new()', 'ui_down'):
            self.assertIn(keyword, script)

    def test_fps_has_camera_light_collisions(self):
        script = starters.files_for('fps3d', 'Test')['game.gd']
        for keyword in ('Camera3D.new()', 'DirectionalLight3D.new()', 'CapsuleShape3D.new()',
                        'BoxShape3D.new()', 'StandardMaterial3D.new()', 'move_and_slide()'):
            self.assertIn(keyword, script)

    def test_fps_has_mouse_release(self):
        script = starters.files_for('fps3d', 'Test')['game.gd']
        self.assertIn('KEY_ESCAPE', script)
        self.assertIn('Input.MOUSE_MODE_VISIBLE', script)

    def test_create_reports_correct_files(self):
        created = starters.create_project(self.dest, 'platformer', 'Test')
        self.assertEqual(created['template'], 'platformer')
        self.assertEqual(set(created['files']), {p.name for p in self.dest.iterdir()})

    def test_generated_bytes_equal_in_memory_templates(self):
        starters.create_project(self.dest, 'topdown', 'Проверка')
        for path, content in starters.files_for('topdown', 'Проверка').items():
            self.assertEqual((self.dest / path).read_bytes(), content.encode('utf-8'))

    def test_refuses_preexisting_project_directory(self):
        self.dest.mkdir()
        original = self.dest / 'project.godot'
        original.write_text('sentinel')
        with self.assertRaisesRegex(starters.StarterError, 'already exists'):
            starters.create_project(self.dest, 'platformer', 'Overwrite')
        self.assertEqual(original.read_text(), 'sentinel')

    def test_refuses_preexisting_empty_directory(self):
        self.dest.mkdir()
        with self.assertRaises(starters.StarterError):
            starters.create_project(self.dest, 'fps3d', 'Test')

    def test_destination_requires_existing_parent(self):
        with self.assertRaises(starters.StarterError):
            starters.create_project(self.root_or_missing(), 'fps3d', 'Test')

    def root_or_missing(self):
        return self.base / 'no_such_parent' / 'game'

    def test_refuse_portability_bad_basename(self):
        names = ('../backtrack', 'game.name', ' ', 'Сцена', '_underscore', 'a' * 65,
                 'CON', 'con', 'AUX', 'NUL', 'COM1', 'LPT9')
        for name in names:
            with self.subTest(name=name), self.assertRaises(starters.StarterError):
                starters.create_project(self.base / name, 'platformer', 'Test')

    def test_accept_portable_folders(self):
        for name in ('a', 'game_1', 'A-game', '5game', 'Z' * 64):
            with self.subTest(name=name):
                target = self.base / name
                starters.create_project(target, 'topdown', 'Test')
                self.assertTrue((target / 'project.godot').is_file())

    def test_refuse_symlinked_parent(self):
        link = self.base / 'link'
        try:
            link.symlink_to(self.base, target_is_directory=True)
        except OSError:
            self.skipTest('symlinks unavailable')
        with self.assertRaises(starters.StarterError):
            starters.create_project(link / 'child', 'platformer', 'Test')

    def test_refuse_symlinked_destination(self):
        try:
            self.dest.symlink_to(self.base, target_is_directory=True)
        except OSError:
            self.skipTest('symlinks unavailable')
        with self.assertRaises(starters.StarterError):
            starters.create_project(self.dest, 'platformer', 'Test')

    def test_refuse_directory_as_project_file(self):
        # The exclusive new-directory requirement avoids all existing-file conflicts.
        self.assertFalse(self.dest.exists())
        starters.create_project(self.dest, 'platformer', 'Test')
        with self.assertRaises(starters.StarterError):
            starters.create_project(self.dest, 'platformer', 'Test')

    def test_cli_platformer_success(self):
        result = self.cli('--template', 'platformer', '--project-name', 'Arcade')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)['template'], 'platformer')
        self.assertTrue((self.dest / 'main.tscn').exists())

    def test_cli_topdown_success(self):
        result = self.cli('--template', 'topdown', '--project-name', 'Quest')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('CircleShape2D', (self.dest / 'game.gd').read_text())

    def test_cli_fps_success(self):
        result = self.cli('--template', 'fps3d', '--project-name', 'Walk')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Camera3D', (self.dest / 'game.gd').read_text())

    def test_cli_invalid_template_returns_two(self):
        self.assertEqual(self.cli('--template', 'unknown').returncode, 2)
        self.assertFalse(self.dest.exists())

    def test_cli_missing_required_template_returns_two(self):
        self.assertEqual(self.cli().returncode, 2)

    def test_cli_existing_returns_two(self):
        self.dest.mkdir()
        result = self.cli('--template', 'platformer')
        self.assertEqual(result.returncode, 2)
        self.assertIn('refusing to overwrite', result.stderr)

    def test_different_names_change_only_metadata(self):
        first = starters.files_for('topdown', 'Alpha')
        second = starters.files_for('topdown', 'Beta')
        self.assertEqual(first['game.gd'], second['game.gd'])
        self.assertEqual(first['main.tscn'], second['main.tscn'])
        self.assertNotEqual(first['project.godot'], second['project.godot'])

    def test_atomic_rollback_on_partial_file_write_failure(self):
        real_open = Path.open
        def fail_on_readme(path, *args, **kwargs):
            if path.name == 'README.md' and args and args[0] == 'x':
                raise OSError('mock disk failure')
            return real_open(path, *args, **kwargs)
        with patch.object(Path, 'open', fail_on_readme):
            with self.assertRaises(OSError):
                starters.create_project(self.dest, 'platformer', 'Test')
        self.assertFalse(self.dest.exists())

    def test_atomic_rollback_preserves_neighbor_directory(self):
        neighbor = self.base / 'neighbor'
        neighbor.mkdir()
        (neighbor / 'save').write_text('untouched')
        with patch.object(Path, 'open', side_effect=OSError('disk failure')):
            with self.assertRaises(OSError):
                starters.create_project(self.dest, 'platformer', 'Test')
        self.assertEqual((neighbor / 'save').read_text(), 'untouched')

    def test_output_files_terminate_with_newline(self):
        for template in starters.TEMPLATES:
            for name, content in starters.files_for(template, 'Demo').items():
                with self.subTest(template=template, file=name):
                    self.assertTrue(content.endswith('\n'))


if __name__ == '__main__':
    unittest.main()
