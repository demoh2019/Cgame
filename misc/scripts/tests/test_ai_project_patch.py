"""Tests for review-first AI edits, stale hash protection, and safe staging."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import ai_project_patch as a


class AIProjectPatchTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.base = Path(temp.name)
        self.root = self.base / 'game'
        self.root.mkdir()
        (self.root / 'project.godot').write_text('[application]\n', encoding='utf8')
        self.plan_path = self.base / 'plan.json'
        self.out = self.base / 'staged'
        self.put('scripts/main.gd', 'extends Node\n')

    def put(self, path, content):
        p = self.root / path
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(content, encoding='utf8')
        return p

    def hash(self, value):
        return hashlib.sha256(value.encode('utf8')).hexdigest()

    def create(self, name='scenes/main.tscn', text='[gd_scene format=3]\n'):
        return {'path': name, 'expected_sha256': None, 'content': text}

    def modify(self, name='scripts/main.gd', text='extends Node2D\n'):
        return {'path': name, 'expected_sha256': self.hash((self.root / name).read_text()), 'content': text}

    def delete(self, name='scripts/main.gd'):
        return {'path': name, 'expected_sha256': self.hash((self.root / name).read_text()), 'delete': True}

    def plan(self, *edits):
        self.plan_path.write_text(json.dumps({'format': 1, 'changes': list(edits)}), encoding='utf8')
        return a.load_plan(self.plan_path)

    def test_preview_only_never_writes(self):
        edits = self.plan(self.modify(), self.create())
        report = a.review(self.root, edits)
        self.assertEqual([x['action'] for x in report['changes']], ['modify', 'create'])
        self.assertIn('-extends Node', report['diff'])
        self.assertFalse(self.out.exists())
        self.assertEqual((self.root / 'scripts/main.gd').read_text(), 'extends Node\n')

    def test_stage_creates_copy_and_original_intact(self):
        edits = self.plan(self.modify(), self.create(), self.create('README.md', 'hello'))
        report = a.review(self.root, edits)
        self.assertEqual(a.stage(self.root, edits, report, self.out), self.out)
        self.assertEqual((self.out / 'scripts/main.gd').read_text(), 'extends Node2D\n')
        self.assertEqual((self.out / 'scenes/main.tscn').read_text(), '[gd_scene format=3]\n')
        self.assertEqual((self.out / 'README.md').read_text(), 'hello')
        self.assertEqual((self.root / 'scripts/main.gd').read_text(), 'extends Node\n')
        self.assertFalse((self.root / 'README.md').exists())
        self.assertTrue((self.out / 'project.godot').exists())

    def test_delete_in_staged_copy_only(self):
        edits = self.plan(self.delete())
        a.stage(self.root, edits, a.review(self.root, edits), self.out)
        self.assertFalse((self.out / 'scripts/main.gd').exists())
        self.assertTrue((self.root / 'scripts/main.gd').exists())

    def test_old_revision_mismatch(self):
        edit = self.modify()
        self.put('scripts/main.gd', 'changed by someone else')
        with self.assertRaisesRegex(a.PatchError, 'Stale'):
            a.review(self.root, self.plan(edit))

    def test_create_existing_rejected(self):
        with self.assertRaisesRegex(a.PatchError, 'overwrite'):
            a.review(self.root, self.plan(self.create('scripts/main.gd')))

    def test_missing_modify_rejected(self):
        edit = self.modify()
        (self.root / 'scripts/main.gd').unlink()
        with self.assertRaisesRegex(a.PatchError, 'missing'):
            a.review(self.root, self.plan(edit))

    def test_case_conflict_with_existing_file(self):
        with self.assertRaises(a.PatchError):
            a.review(self.root, self.plan(self.create('scripts/Main.gd')))

    def test_duplicate_plan_paths(self):
        with self.assertRaises(a.PatchError):
            self.plan(self.create('a.gd'), self.create('A.gd'))

    def test_unsupported_extension(self):
        with self.assertRaises(a.PatchError):
            self.plan(self.create('binary.exe'))

    def test_directory_traversal(self):
        for value in ['../bad.gd', '/tmp/bad.gd', 'a/../bad.gd', 'a//bad.gd', 'a\\bad.gd', 'C:/bad.gd']:
            with self.subTest(path=value), self.assertRaises(a.PatchError):
                self.plan(self.create(value))

    def test_hidden_and_reserved_components(self):
        for value in ['.env', '.private/config.gd', 'addons/plugin.gd', 'ai_generated/a.gd', 'CON.md', 'x/LPT1.gd', 'bad .gd']:
            with self.subTest(path=value), self.assertRaises(a.PatchError):
                self.plan(self.create(value))

    def test_non_nfc_path(self):
        with self.assertRaises(a.PatchError):
            self.plan(self.create('cafe\u0301.gd'))

    def test_valid_unicode_path(self):
        edits = self.plan(self.create('scenes/café.gd', 'extends Node\n'))
        a.stage(self.root, edits, a.review(self.root, edits), self.out)
        self.assertTrue((self.out / 'scenes/café.gd').is_file())

    def test_editing_gd_tool_scripts_forbidden(self):
        with self.assertRaisesRegex(a.PatchError, 'editor-executable'):
            self.plan(self.create('plugin.gd', '@tool\nextends EditorPlugin'))

    def test_file_too_large(self):
        with self.assertRaises(a.PatchError):
            self.plan(self.create('big.txt', 'x' * (a.MAX_FILE_BYTES + 1)))

    def test_max_changes(self):
        with self.assertRaises(a.PatchError):
            self.plan(*(self.create(f'file{i}.txt') for i in range(21)))

    def test_empty_plan(self):
        with self.assertRaises(a.PatchError):
            self.plan()

    def test_unsupported_format(self):
        self.plan_path.write_text('{"format":2,"changes":[]}')
        with self.assertRaises(a.PatchError):
            a.load_plan(self.plan_path)

    def test_ambiguous_fields(self):
        bad = dict(self.create(), command='rm -rf')
        with self.assertRaises(a.PatchError):
            self.plan(bad)

    def test_delete_requires_hash(self):
        with self.assertRaises(a.PatchError):
            self.plan({'path': 'scripts/main.gd', 'expected_sha256': None, 'delete': True})

    def test_invalid_hash_format(self):
        with self.assertRaises(a.PatchError):
            self.plan({'path': 'scripts/main.gd', 'expected_sha256': 'abc', 'content': 'abc'})

    def test_no_op_edit_rejected(self):
        with self.assertRaises(a.PatchError):
            a.review(self.root, self.plan(self.modify(text='extends Node\n')))

    def test_directory_conflict_from_creation(self):
        edits = self.plan(self.create('scripts/main.gd/child.txt', 'abc'))
        with self.assertRaises(a.PatchError):
            a.review(self.root, edits)

    def test_directory_conflict_between_creates(self):
        edits = self.plan(self.create('foo.gd'), self.create('foo.gd/bar.txt'))
        with self.assertRaises(a.PatchError):
            a.review(self.root, edits)

    def test_deleted_file_can_become_a_directory(self):
        # A deleted file must not trigger a false parent-directory conflict.
        edits = self.plan(self.delete(), self.create('scripts/main.gd/child.txt', 'generated'))
        report = a.review(self.root, edits)
        self.assertEqual([change['action'] for change in report['changes']], ['delete', 'create'])
        a.stage(self.root, edits, report, self.out)
        self.assertTrue((self.out / 'scripts/main.gd' / 'child.txt').is_file())
        self.assertTrue((self.root / 'scripts/main.gd').is_file())

    def test_large_project_with_multiple_deletions(self):
        # Mock only the file scan and reads: validation must still correctly
        # handle a nearly full 20k-file snapshot with many deleted paths.
        paths = [f'assets/file_{i:05d}.gd' for i in range(19999)]
        deletes = [
            {'path': paths[i], 'expected_sha256': self.hash('extends Node\n'), 'delete': True}
            for i in range(18)
        ]
        edits = self.plan(*deletes, self.create('assets/new_script.gd', 'extends Node2D\n'))
        with patch.object(a, '_scan_project', return_value=paths):
            with patch.object(a, '_read_regular', return_value=b'extends Node\n'):
                report = a.review(self.root, edits)
        self.assertTrue(report['ok'])
        self.assertEqual(len(report['changes']), 19)
        self.assertEqual([change['action'] for change in report['changes']].count('delete'), 18)

    def test_existing_output_is_preserved(self):
        edits = self.plan(self.create())
        self.out.mkdir()
        sentinel = self.out / 'keep'
        sentinel.write_text('original')
        with self.assertRaises(a.PatchError):
            a.stage(self.root, edits, a.review(self.root, edits), self.out)
        self.assertEqual(sentinel.read_text(), 'original')

    def test_output_inside_original_rejected(self):
        edits = self.plan(self.create())
        with self.assertRaises(a.PatchError):
            a.stage(self.root, edits, a.review(self.root, edits), self.root / 'stage')

    def test_missing_output_parent_rejected(self):
        edits = self.plan(self.create())
        with self.assertRaises(a.PatchError):
            a.stage(self.root, edits, a.review(self.root, edits), self.base / 'missing' / 'stage')

    def test_symlink_in_source_rejected(self):
        try:
            (self.root / 'link.gd').symlink_to(self.root / 'scripts/main.gd')
        except OSError:
            self.skipTest('symlinks unsupported')
        with self.assertRaises(a.PatchError):
            a.review(self.root, self.plan(self.create()))

    def test_symlink_directory_rejected(self):
        try:
            (self.root / 'linked').symlink_to(self.root / 'scripts', target_is_directory=True)
        except OSError:
            self.skipTest('symlinks unsupported')
        with self.assertRaises(a.PatchError):
            a.review(self.root, self.plan(self.create()))

    def test_symlink_output_rejected(self):
        edits = self.plan(self.create())
        try:
            self.out.symlink_to(self.base / 'outside', target_is_directory=True)
        except OSError:
            self.skipTest('symlinks unsupported')
        with self.assertRaises(a.PatchError):
            a.stage(self.root, edits, a.review(self.root, edits), self.out)

    def test_invalid_utf8_existing_content_rejected(self):
        (self.root / 'scripts/main.gd').write_bytes(b'\xff\x00')
        self.plan_path.write_text(json.dumps({'format': 1, 'changes': [{'path':'scripts/main.gd','expected_sha256':hashlib.sha256(b'\xff\x00').hexdigest(),'content':'valid'}]}))
        with self.assertRaises(a.PatchError):
            a.review(self.root, a.load_plan(self.plan_path))

    def test_skip_godot_generated_cache(self):
        (self.root / '.godot').mkdir()
        (self.root / '.godot' / 'huge.bin').write_bytes(b'x' * 200)
        edits = self.plan(self.create())
        a.stage(self.root, edits, a.review(self.root, edits), self.out)
        self.assertFalse((self.out / '.godot').exists())

    def test_project_limit_exceeded(self):
        edits = self.plan(self.create())
        with patch.object(a, 'MAX_PROJECT_FILES', 1):
            with self.assertRaises(a.PatchError):
                a.review(self.root, edits)

    def test_failure_rolls_back_partial_staging(self):
        edits = self.plan(self.create())
        report = a.review(self.root, edits)
        original = a.review
        def fail_on_staged(root, changes):
            if root != self.root:
                raise a.PatchError('simulated staged failure')
            return original(root, changes)
        with patch.object(a, 'review', side_effect=fail_on_staged):
            with self.assertRaises(a.PatchError):
                a.stage(self.root, edits, report, self.out)
        self.assertFalse(self.out.exists())
        self.assertFalse(list(self.base.glob('.ai-patch-*')))

    def test_source_changed_during_staging_rejected(self):
        edits = self.plan(self.modify())
        report = a.review(self.root, edits)
        original = a.review
        def change_on_staged(root, changes):
            if root != self.root:
                (root / 'scripts/main.gd').write_text('changed')
            return original(root, changes)
        with patch.object(a, 'review', side_effect=change_on_staged):
            with self.assertRaises(a.PatchError):
                a.stage(self.root, edits, report, self.out)
        self.assertFalse(self.out.exists())

    def test_missing_project_godot(self):
        (self.root / 'project.godot').unlink()
        with self.assertRaises(a.PatchError):
            a.review(self.root, self.plan(self.create()))

    def test_cli_review_and_stage(self):
        self.plan(self.create())
        cli = [sys.executable, str(Path(a.__file__)), str(self.root), str(self.plan_path)]
        result = subprocess.run(cli, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.out.exists())
        self.assertEqual(json.loads(result.stdout)['changes'][0]['action'], 'create')
        result = subprocess.run(cli + ['--stage', str(self.out)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)['staged_to'], str(self.out))
        self.assertTrue((self.out / 'scenes/main.tscn').exists())

    def test_cli_error_exit(self):
        self.plan_path.write_text('bad json')
        result = subprocess.run([sys.executable, str(Path(a.__file__)), str(self.root), str(self.plan_path)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn('ai_project_patch:', result.stderr)


if __name__ == '__main__':
    unittest.main()
