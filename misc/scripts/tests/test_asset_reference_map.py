"""Offline tests for reference graph/source-size estimation."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import asset_reference_map as arm


class ReferenceMapTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.project = Path(self.temp.name) / 'game'
        self.project.mkdir()
        self.put('project.godot', '')

    def put(self, name, content):
        path = self.project / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content.encode('utf-8') if isinstance(content, str) else content)
        return path

    def run_map(self, *roots, **kwargs):
        return arm.build_reference_map(self.project, list(roots), **kwargs)

    def cli(self, *arguments):
        return subprocess.run([sys.executable, arm.__file__, str(self.project), *arguments],
                              text=True, capture_output=True, check=False)

    def test_single_binary_root(self):
        self.put('a.png', b'1234')
        report = self.run_map('res://a.png')
        self.assertEqual(report['combined']['total_bytes'], 4)
        self.assertEqual(report['combined']['file_count'], 1)

    def test_scene_external_resource(self):
        scene = '[ext_resource type="Texture2D" path="res://art/a.png" id="1"]'
        self.put('level.tscn', scene)
        self.put('art/a.png', b'123')
        report = self.run_map('level.tscn')
        self.assertEqual(report['combined']['file_count'], 2)
        self.assertEqual(report['references']['res://level.tscn'], ['res://art/a.png'])
        self.assertEqual(report['referenced_by']['res://art/a.png'], ['res://level.tscn'])

    def test_nested_scene_recursive(self):
        self.put('main.tscn', 'path="res://sub.tscn"')
        self.put('sub.tscn', 'path="res://icon.png"')
        self.put('icon.png', b'1234')
        self.assertEqual(self.run_map('main.tscn')['combined']['file_count'], 3)

    def test_shared_dependency_counted_once(self):
        self.put('first.tscn', 'path="res://shared.png"')
        self.put('second.tscn', 'path="res://shared.png"')
        self.put('shared.png', b'12345')
        report = self.run_map('first.tscn', 'second.tscn')
        self.assertEqual(report['combined']['file_count'], 3)
        self.assertEqual(report['combined']['total_bytes'],
                         sum(len((self.project / x).read_bytes()) for x in ('first.tscn', 'second.tscn', 'shared.png')))
        self.assertEqual(report['referenced_by']['res://shared.png'], ['res://first.tscn', 'res://second.tscn'])

    def test_cycle_terminates(self):
        self.put('a.tres', 'path="res://b.tres"')
        self.put('b.tres', 'path="res://a.tres"')
        self.assertEqual(self.run_map('a.tres')['combined']['file_count'], 2)

    def test_self_reference_terminates(self):
        self.put('a.tres', 'path="res://a.tres"')
        self.assertEqual(self.run_map('a.tres')['references']['res://a.tres'], ['res://a.tres'])

    def test_duplicate_direct_reference_deduplicated(self):
        self.put('a.tres', 'path="res://c.png" path="res://c.png"')
        self.put('c.png', b'1')
        self.assertEqual(self.run_map('a.tres')['references']['res://a.tres'], ['res://c.png'])

    def test_gd_load_and_preload(self):
        self.put('main.gd', 'var x = preload("res://a.png")\nvar y=load(\'res://b.tres\')')
        self.put('a.png', b'1')
        self.put('b.tres', '')
        self.assertEqual(self.run_map('main.gd')['combined']['file_count'], 3)

    def test_comments_ignored_in_gd(self):
        self.put('main.gd', '# "res://not_found.png"\nvar x="res://ok.png" # "res://missing2.png"')
        self.put('ok.png', b'123')
        self.assertFalse(self.run_map('main.gd')['problems'])

    def test_shader_include_preserved(self):
        self.put('a.gdshader', '#include "res://utils.gdshaderinc" // "res://missing.png"')
        self.put('utils.gdshaderinc', 'shader code')
        self.assertEqual(self.run_map('a.gdshader')['references']['res://a.gdshader'], ['res://utils.gdshaderinc'])

    def test_cpp_multiline_comment_ignored(self):
        self.put('a.cs', '/* "res://bad.png"\n"res://also_bad.png" */\nvar x="res://good.png";')
        self.put('good.png', b'1')
        self.assertFalse(self.run_map('a.cs')['problems'])

    def test_comment_marker_inside_quotes_preserved(self):
        self.put('a.tscn', 'path="res://a#b.png"')
        self.put('a#b.png', b'1')
        self.assertFalse(self.run_map('a.tscn')['problems'])

    def test_csharp_http_comment_inside_quote(self):
        self.put('a.cs', 'var x="res://textures//x.png"; // comment')
        self.put('textures/x.png', b'1')
        self.assertEqual(self.run_map('a.cs')['problems'][0]['kind'], 'invalid')

    def test_missing_path_diagnostic(self):
        self.put('a.tscn', 'path="res://missing.png"')
        report = self.run_map('a.tscn')
        self.assertEqual(report['problems'], [{'source': 'a.tscn', 'reference': 'res://missing.png', 'kind': 'missing'}])

    def test_case_mismatch_diagnostic(self):
        self.put('a.tscn', 'path="res://Icon.png"')
        self.put('icon.png', b'123')
        report = self.run_map('a.tscn')
        self.assertEqual(report['problems'][0]['kind'], 'case_mismatch')
        self.assertEqual(report['problems'][0]['actual'], 'res://icon.png')

    def test_invalid_traversal_diagnostic(self):
        self.put('a.tscn', 'path="res://../outside.png"')
        self.assertEqual(self.run_map('a.tscn')['problems'][0]['kind'], 'invalid')

    def test_invalid_absolute_diagnostic(self):
        self.put('a.tscn', 'path="res:///tmp/secret"')
        self.assertEqual(self.run_map('a.tscn')['problems'][0]['kind'], 'invalid')

    def test_invalid_windows_name_diagnostic(self):
        self.put('a.tscn', 'path="res://COM1.png"')
        self.assertEqual(self.run_map('a.tscn')['problems'][0]['kind'], 'invalid')

    def test_escaped_backslash_invalid(self):
        self.put('a.tscn', r'path="res://foo\\bar.png"')
        self.assertEqual(self.run_map('a.tscn')['problems'][0]['kind'], 'invalid')

    def test_ignore_irrelevant_broken_assets(self):
        self.put('good.tscn', 'path="res://exists.png"')
        self.put('broken.tscn', 'path="res://missing.png"')
        self.put('exists.png', b'12')
        self.assertFalse(self.run_map('good.tscn')['problems'])

    def test_unknown_root_fails(self):
        with self.assertRaises(arm.ReferenceMapError):
            self.run_map('missing.tscn')

    def test_root_traversal_fails(self):
        with self.assertRaises(arm.ReferenceMapError):
            self.run_map('res://../outside')

    def test_no_roots_fails(self):
        with self.assertRaises(arm.ReferenceMapError):
            self.run_map()

    def test_many_roots_fails(self):
        with self.assertRaises(arm.ReferenceMapError):
            self.run_map(*(['project.godot'] * (arm.MAX_ROOTS + 1)))

    def test_repeat_roots_deduplicated(self):
        self.put('a.tscn', '')
        self.assertEqual(len(self.run_map('a.tscn', 'res://a.tscn')['roots']), 1)

    def test_limit_exceeded(self):
        self.put('a.png', b'abc')
        self.assertTrue(self.run_map('a.png', max_total_bytes=2)['budget']['exceeded'])

    def test_limit_equal_allowed(self):
        self.put('a.png', b'abc')
        self.assertFalse(self.run_map('a.png', max_total_bytes=3)['budget']['exceeded'])

    def test_negative_budget_rejected(self):
        with self.assertRaises(arm.ReferenceMapError):
            self.run_map('project.godot', max_total_bytes=-1)

    def test_boolean_budget_rejected(self):
        with self.assertRaises(arm.ReferenceMapError):
            self.run_map('project.godot', max_total_bytes=True)

    def test_text_size_cap_rejected(self):
        self.put('a.tscn', '1234567')
        with self.assertRaises(arm.ReferenceMapError):
            self.run_map('a.tscn', max_text_bytes=2)

    def test_invalid_utf8_rejected(self):
        self.put('a.tscn', b'\xff')
        with self.assertRaises(arm.ReferenceMapError):
            self.run_map('a.tscn')

    def test_binary_resource_never_decoded(self):
        self.put('binary.png', b'\xff\x00\x01')
        self.assertEqual(self.run_map('binary.png')['combined']['total_bytes'], 3)

    def test_stable_json(self):
        self.put('a.tscn', 'path="res://b.png"')
        self.put('b.png', b'1')
        self.assertEqual(json.dumps(self.run_map('a.tscn'), sort_keys=True),
                         json.dumps(self.run_map('a.tscn'), sort_keys=True))

    def test_cli_json_ok(self):
        self.put('a.png', b'abc')
        result = self.cli('--root', 'res://a.png', '--format', 'json')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)['combined']['total_bytes'], 3)

    def test_cli_missing_ref_exit_one(self):
        self.put('a.tscn', 'path="res://missing.png"')
        result = self.cli('--root', 'a.tscn', '--format', 'json')
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertEqual(json.loads(result.stdout)['problems'][0]['kind'], 'missing')

    def test_cli_budget_exit_one(self):
        self.put('a.png', b'12345')
        result = self.cli('--root', 'a.png', '--max-total-bytes', '4')
        self.assertEqual(result.returncode, 1)
        self.assertIn('BUDGET EXCEEDED', result.stdout)

    def test_cli_invalid_project_exit_two(self):
        (self.project / 'project.godot').unlink()
        self.assertEqual(self.cli('--root', 'a.png').returncode, 2)

    def test_cli_rejects_negative_budget(self):
        self.assertEqual(self.cli('--root', 'project.godot', '--max-total-bytes', '-1').returncode, 2)

    def test_symlink_asset_rejected(self):
        target = self.put('a.png', b'1')
        try:
            (self.project / 'shortcut.png').symlink_to(target)
        except (NotImplementedError, OSError):
            self.skipTest('Symlinks unavailable')
        with self.assertRaises(arm.AssetSizeError):
            self.run_map('a.png')

    def test_case_colliding_paths_rejected(self):
        self.put('A.png', b'1')
        self.put('a.png', b'1')
        if not (self.project / 'A.png').exists() or not (self.project / 'a.png').exists():
            self.skipTest('Case insensitive FS')
        with self.assertRaises(arm.AssetSizeError):
            self.run_map('project.godot')

    def test_empty_reference_invalid(self):
        self.put('a.tscn', 'path="res://"')
        self.assertEqual(self.run_map('a.tscn')['problems'][0]['kind'], 'invalid')

    def test_references_in_tres(self):
        self.put('a.tres', '[ext_resource path="res://b.tres"]')
        self.put('b.tres', '')
        self.assertEqual(self.run_map('a.tres')['combined']['file_count'], 2)

    def test_reference_escaping_quote_does_not_crash(self):
        self.put('a.tscn', 'name="some \\" quoted" path="res://b.tres"')
        self.put('b.tres', '')
        self.assertEqual(self.run_map('a.tscn')['combined']['file_count'], 2)

    def test_json_paths_no_absolute_leak(self):
        self.put('a.tscn', '')
        self.assertNotIn(str(self.project), json.dumps(self.run_map('a.tscn')))


if __name__ == '__main__':
    unittest.main()
