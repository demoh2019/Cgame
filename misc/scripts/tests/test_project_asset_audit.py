#!/usr/bin/env python3
"""Tests for the portable, stdlib-only Godot project asset auditor."""

from __future__ import annotations

from contextlib import redirect_stdout, redirect_stderr
from io import StringIO
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from project_asset_audit import main, scan_project  # noqa: E402


class AssetAuditTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)

    def write(self, name, content):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        if isinstance(content, bytes):
            path.write_bytes(content)
        else:
            path.write_text(content, encoding="utf-8")
        return path

    def codes(self):
        return [finding.code for finding in scan_project(self.root).findings]

    def test_empty_project(self):
        report = scan_project(self.root)
        self.assertEqual(report.errors, 0)
        self.assertEqual(report.files_scanned, 0)

    def test_valid_quoted_scene_reference(self):
        self.write("assets/sprite.png", b"PNG")
        self.write("world.tscn", '[ext_resource type="Texture2D" path="res://assets/sprite.png" id="1"]')
        self.assertEqual(self.codes(), [])

    def test_quoted_filename_may_contain_spaces(self):
        self.write("assets/wood floor.png", b"PNG")
        self.write("scene.tscn", 'path="res://assets/wood floor.png"')
        self.assertEqual(self.codes(), [])

    def test_missing_gdscript_preload(self):
        self.write("main.gd", 'var icon = preload("res://images/not-there.png")')
        self.assertEqual(self.codes(), ["MISSING_RESOURCE"])

    def test_case_mismatch_found(self):
        self.write("Textures/Hero.PNG", b"PNG")
        self.write("main.gd", 'var a = load("res://textures/hero.png")')
        self.assertEqual(self.codes(), ["CASE_MISMATCH"])

    def test_case_collision_files(self):
        self.write("A.png", b"A")
        self.write("a.png", b"B")
        self.assertEqual(self.codes().count("CASE_COLLISION"), 2)

    def test_case_collision_directories(self):
        self.write("Scenes/first.gd", "pass")
        self.write("scenes/second.gd", "pass")
        self.assertEqual(self.codes().count("CASE_COLLISION"), 2)

    def test_unicode_casefold_collision(self):
        self.write("Straße.png", b"A")
        self.write("STRASSE.png", b"B")
        self.assertEqual(self.codes().count("CASE_COLLISION"), 2)

    def test_parent_traversal_detected(self):
        self.write("main.gd", 'var a = load("res://../../password.txt")')
        self.assertEqual(self.codes(), ["INVALID_RESOURCE_PATH"])

    def test_absolute_resource_path_detected(self):
        self.write("main.gd", 'var a = load("res:///etc/passwd")')
        self.assertEqual(self.codes(), ["INVALID_RESOURCE_PATH"])

    def test_backslashes_detected(self):
        self.write("main.gd", "var a = load('res://folder\\some.tres')")
        self.assertEqual(self.codes(), ["INVALID_SEPARATOR"])

    def test_empty_resource_path(self):
        self.write("main.gd", 'var a = load("res://")')
        self.assertEqual(self.codes(), ["EMPTY_RESOURCE_PATH"])

    def test_directory_cannot_be_loaded(self):
        self.write("assets/a.png", b"DATA")
        self.write("main.gd", 'var a = load("res://assets")')
        self.assertEqual(self.codes(), ["RESOURCE_IS_DIRECTORY"])

    def test_full_line_comments_ignored(self):
        self.write("main.gd", '# var a = load("res://missing.tres")\npass')
        self.assertEqual(self.codes(), [])

    def test_shader_includes_are_scanned(self):
        self.write("shader.gdshader", '#include "res://shaders/common.gdshaderinc"')
        self.assertEqual(self.codes(), ["MISSING_RESOURCE"])

    def test_generations_directory_ignored(self):
        self.write(".godot/imported/private.gd", 'load("res://missing.tres")')
        self.write(".git/hooks/test.gd", 'load("res://missing.tres")')
        self.write("main.gd", 'load("res://.godot/imported/cache.ctex")')
        self.assertEqual(self.codes(), [])

    def test_unquoted_nonresource_prose_ignored(self):
        self.write("main.gd", 'var description = "See res://missing.png for more"')
        self.assertEqual(self.codes(), [])

    def test_exclude_globs(self):
        self.write("vendor/bad.gd", 'preload("res://missing.png")')
        self.write("main.gd", "pass")
        report = scan_project(self.root, exclude=("vendor/*",))
        self.assertEqual(report.errors, 0)
        self.assertEqual(report.files_scanned, 1)

    def test_file_too_large_is_warning(self):
        self.write("main.gd", "a" * 15)
        report = scan_project(self.root, max_text_bytes=8)
        self.assertEqual([f.code for f in report.findings], ["FILE_TOO_LARGE"])
        self.assertEqual(report.errors, 0)

    def test_invalid_utf8_is_warning(self):
        self.write("main.gd", b"\xff\xfe")
        self.assertEqual(self.codes(), ["INVALID_UTF8"])

    def test_invalid_configuration_raises(self):
        with self.assertRaises(ValueError):
            scan_project(self.root / "not_a_directory")
        with self.assertRaises(ValueError):
            scan_project(self.root, max_text_bytes=0)

    def test_report_sorting_and_counts_deterministic(self):
        self.write("z.gd", 'load("res://missing_b.png")\nload("res://missing_a.png")')
        self.write("a.gd", 'load("res://missing_c.png")')
        first = scan_project(self.root)
        second = scan_project(self.root)
        self.assertEqual(first.to_dict(), second.to_dict())
        self.assertEqual(first.references_checked, 3)
        self.assertEqual(first.errors, 3)
        self.assertEqual([f.source for f in first.findings], ["a.gd", "z.gd", "z.gd"])

    def test_cli_text_exit_code(self):
        self.write("broken.gd", 'load("res://missing.tres")')
        output = StringIO()
        with redirect_stdout(output):
            result = main([str(self.root)])
        self.assertEqual(result, 1)
        self.assertIn("MISSING_RESOURCE", output.getvalue())

    def test_cli_json_has_machine_readable_summary(self):
        self.write("main.gd", "pass")
        output = StringIO()
        with redirect_stdout(output):
            result = main([str(self.root), "--format", "json"])
        self.assertEqual(result, 0)
        payload = json.loads(output.getvalue())
        self.assertEqual(payload["summary"]["files_scanned"], 1)
        self.assertEqual(payload["summary"]["references_checked"], 0)

    def test_cli_warn_as_failure(self):
        self.write("main.gd", b"\xff")
        with redirect_stdout(StringIO()):
            self.assertEqual(main([str(self.root)]), 0)
            self.assertEqual(main([str(self.root), "--fail-on-warning"]), 1)

    def test_cli_invalid_directory_returns_two(self):
        with redirect_stderr(StringIO()):
            self.assertEqual(main([str(self.root / "missing")]), 2)

    @unittest.skipUnless(hasattr(os, "symlink"), "Symlinks unsupported")
    def test_external_symlink_is_flagged_and_not_followed(self):
        with tempfile.TemporaryDirectory() as external:
            p = Path(external) / "outside.gd"
            p.write_text('load("res://missing.png")', encoding="utf-8")
            try:
                (self.root / "linked.gd").symlink_to(p)
            except OSError:
                self.skipTest("Insufficient privileges for symlink")
            self.assertEqual(self.codes(), ["EXTERNAL_SYMLINK"])


if __name__ == "__main__":
    unittest.main()
