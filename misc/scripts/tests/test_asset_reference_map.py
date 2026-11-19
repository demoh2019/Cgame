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

    def test_large_unquoted_source_scans_without_false_references(self):
        # Ordinary source is the common case in large scripts/shaders.
        prelude = "ordinary_identifier_with_arguments_123456789012345\n" * 8000
        for suffix in ('.gd', '.cs', '.gdextension'):
            with self.subTest(suffix=suffix):
                self.assertEqual(
                    arm._references(prelude + '"res://assets/hero.png"', suffix),
                    ['assets/hero.png'])

    def test_token_skip_preserves_comment_and_escaped_quote_rules(self):
        examples = [
            ('.gd',
             '# "res://ignored.png"\nvar x = "res://a.png" # "res://also_ignored.png"\n'
             "var y = 'res://b.png'\n",
             ['a.png', 'b.png']),
            ('.cs',
             '/* "res://ignored.png" */\nvar x = "res://a.png"; // "res://wrong.png"\n'
             "var y = 'res://b.png';\n",
             ['a.png', 'b.png']),
            ('.gdshader',
             '#include "res://a.gdshaderinc" // "res://wrong.png"\n',
             ['a.gdshaderinc']),
        ]
        for suffix, source, expected in examples:
            with self.subTest(suffix=suffix):
                self.assertEqual(arm._references(source, suffix), expected)

    def test_literal_fastpath_matches_character_scanner_on_random_inputs(self):
        import random

        # Legacy character-by-character string scanner is an independent
        # correctness oracle for quotes, escapes and comments.
        def legacy_references(text, suffix):
            results = set()
            index = 0
            length = len(text)
            block_comment = False
            hash_comments = suffix in {".gd", ".tscn", ".tres"}
            cpp_comments = suffix in {".cs", ".gdshader", ".gdshaderinc", ".shader"}
            tokens = (arm._HASH_TOKENS if hash_comments else
                      arm._CPP_TOKENS if cpp_comments else arm._QUOTE_TOKENS)
            while index < length:
                if block_comment:
                    closing = text.find("*/", index)
                    if closing < 0:
                        break
                    block_comment = False
                    index = closing + 2
                    continue
                token = tokens.search(text, index)
                if token is None:
                    break
                index = token.start()
                char = text[index]
                if hash_comments and char == "#":
                    ending = text.find("\n", index)
                    index = length if ending < 0 else ending + 1
                    continue
                if cpp_comments and text.startswith("//", index):
                    ending = text.find("\n", index)
                    index = length if ending < 0 else ending + 1
                    continue
                if cpp_comments and text.startswith("/*", index):
                    block_comment = True
                    index += 2
                    continue
                if char in ("'", '"'):
                    quote = char
                    index += 1
                    value = []
                    terminated = False
                    while index < length:
                        character = text[index]
                        if character == "\\" and index + 1 < length:
                            value.append(character)
                            value.append(text[index + 1])
                            index += 2
                            continue
                        if character == quote:
                            terminated = True
                            index += 1
                            break
                        value.append(character)
                        index += 1
                    if terminated:
                        candidate = "".join(value)
                        if candidate.startswith("res://"):
                            results.add(candidate[6:])
                    continue
                index += 1
            return sorted(results)

        rng = random.Random(58123)
        alphabet = "abc0123/#'\"\\ \n:\t*()"
        for suffix in (".gd", ".cs", ".gdshader", ".tscn", ".gdextension"):
            for case in range(500):
                text = "".join(rng.choice(alphabet)
                               for _ in range(rng.randrange(0, 300)))
                if case % 4 == 0:
                    text = '"res://a\\\"/b.png"' + text + "'res://a/b.tres'"
                with self.subTest(suffix=suffix, case=case):
                    self.assertEqual(arm._references(text, suffix),
                                     legacy_references(text, suffix))

    def test_many_irrelevant_strings_do_not_hide_real_asset_reference(self):
        content = ('var text = "' + 'x' * 512 + '";\n') * 2000
        content += 'var asset = "res://sprites/hero.png";\n'
        self.assertEqual(arm._references(content, ".cs"), ['sprites/hero.png'])

    def test_dense_shared_reference_graph_preserves_sorted_outputs(self):
        count = 72
        for i in range(count):
            references = "".join(
                f'path="res://nodes/{j:03}.tres"\n'
                for j in range(count) if j != i
            )
            self.put(f"nodes/{i:03}.tres", references)
        report = self.run_map("nodes/000.tres", "nodes/071.tres")
        self.assertEqual([root["file_count"] for root in report["roots"]], [72, 72])
        self.assertEqual(report["combined"]["file_count"], 72)
        self.assertEqual(report["combined"]["total_bytes"],
                         sum((self.project / f"nodes/{i:03}.tres").stat().st_size
                             for i in range(count)))
        self.assertEqual(report["references"]["res://nodes/000.tres"],
                         [f"res://nodes/{i:03}.tres" for i in range(1, count)])
        for incoming in report["referenced_by"].values():
            self.assertEqual(incoming, sorted(incoming))
            self.assertEqual(len(incoming), count - 1)
        self.assertFalse(report["problems"])

    def test_diamond_and_cycle_counted_once_for_each_root(self):
        self.put("main.tscn", 'path="res://left.tscn" path="res://right.tscn"')
        self.put("left.tscn", 'path="res://common.tscn"')
        self.put("right.tscn", 'path="res://common.tscn"')
        self.put("common.tscn", 'path="res://main.tscn"')
        report = self.run_map("left.tscn", "main.tscn")
        self.assertEqual([row["root"] for row in report["roots"]],
                         ["res://left.tscn", "res://main.tscn"])
        self.assertEqual([row["file_count"] for row in report["roots"]], [4, 4])
        self.assertEqual(report["combined"]["file_count"], 4)
        self.assertEqual(report["referenced_by"]["res://common.tscn"],
                         ["res://left.tscn", "res://right.tscn"])

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
