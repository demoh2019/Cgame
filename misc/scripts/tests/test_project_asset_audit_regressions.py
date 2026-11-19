#!/usr/bin/env python3
"""Additional regression tests for static asset reference auditing."""

from __future__ import annotations

from contextlib import redirect_stdout
from io import StringIO
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from project_asset_audit import main, scan_project  # noqa: E402


class AssetAuditRegressionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    def write(self, name, text=""):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        return path

    def findings(self):
        return scan_project(self.root).findings

    def test_inline_gdscript_comment_is_ignored(self):
        self.write("game.gd", 'var x = 1 # preload("res://missing.tres")')
        self.assertEqual(self.findings(), [])

    def test_inline_gdscript_comment_after_valid_reference(self):
        self.write("assets/valid.tres")
        self.write("game.gd", 'preload("res://assets/valid.tres") # preload("res://missing.tres")')
        report = scan_project(self.root)
        self.assertEqual(report.references_checked, 1)
        self.assertEqual(report.errors, 0)

    def test_gdscript_comment_marker_inside_string_does_not_truncate(self):
        self.write("assets/valid.tres")
        self.write("game.gd", 'var tag = "#tag"; var asset = load("res://assets/valid.tres")')
        self.assertEqual(scan_project(self.root).references_checked, 1)
        self.assertEqual(self.findings(), [])

    def test_hash_in_resource_filename_remains_valid(self):
        self.write("assets/#variant.tres")
        self.write("game.gd", 'preload("res://assets/#variant.tres")')
        self.assertEqual(self.findings(), [])

    def test_escaped_quote_before_hash_does_not_create_comment(self):
        self.write("assets/ok.tres")
        self.write("game.gd", 'var label = "escaped \\"#\\" label"; var a = load("res://assets/ok.tres")')
        self.assertEqual(scan_project(self.root).references_checked, 1)
        self.assertEqual(self.findings(), [])

    def test_csharp_inline_comment_is_ignored(self):
        self.write("src/Game.cs", 'var x = 1; // GD.Load("res://missing.tres");')
        self.assertEqual(self.findings(), [])

    def test_csharp_valid_reference_before_inline_comment(self):
        self.write("assets/ok.tres")
        self.write("src/Game.cs", 'GD.Load("res://assets/ok.tres"); // GD.Load("res://missing.tres")')
        self.assertEqual(scan_project(self.root).references_checked, 1)
        self.assertEqual(self.findings(), [])

    def test_url_inside_csharp_literal_does_not_start_comment(self):
        self.write("assets/ok.tres")
        self.write("src/Game.cs", 'var site = "https://example.com"; GD.Load("res://assets/ok.tres");')
        self.assertEqual(scan_project(self.root).references_checked, 1)
        self.assertEqual(self.findings(), [])

    def test_shader_inline_comment_reference_is_ignored(self):
        self.write("shader.gdshader", 'void fragment() {} // #include "res://missing.gdshaderinc"')
        self.assertEqual(self.findings(), [])

    def test_shader_include_is_not_treated_as_comment(self):
        self.write("shader.gdshader", '#include "res://missing.gdshaderinc"')
        self.assertEqual([f.code for f in self.findings()], ["MISSING_RESOURCE"])

    def test_shader_include_and_trailing_comment(self):
        self.write("includes/ok.gdshaderinc")
        self.write("shader.gdshader", '#include "res://includes/ok.gdshaderinc" // "res://missing.gdshaderinc"')
        self.assertEqual(scan_project(self.root).references_checked, 1)
        self.assertEqual(self.findings(), [])

    def test_repeated_missing_references_report_each_occurrence(self):
        self.write("scene.tscn", 'path="res://missing.tres"\npath="res://missing.tres"')
        report = scan_project(self.root)
        self.assertEqual(report.references_checked, 2)
        self.assertEqual([f.line for f in report.findings], [1, 2])

    def test_case_mismatch_in_nested_directory(self):
        self.write("Textures/Hero.PNG")
        self.write("scene.tscn", 'path="res://textures/hero.png"')
        self.assertEqual([f.code for f in self.findings()], ["CASE_MISMATCH"])

    def test_maximum_text_size_is_inclusive(self):
        self.write("game.gd", 'load("res://missing.tres")')
        size = (self.root / "game.gd").stat().st_size
        report = scan_project(self.root, max_text_bytes=size)
        self.assertEqual([f.code for f in report.findings], ["MISSING_RESOURCE"])

    def test_unscanned_text_extension_is_not_checked(self):
        self.write("notes.txt", 'load("res://missing.tres")')
        self.assertEqual(scan_project(self.root).references_checked, 0)
        self.assertEqual(self.findings(), [])

    def test_cli_json_summary_counts_all_missing_references(self):
        self.write("scene.tscn", 'path="res://first.tres"\npath="res://second.tres"')
        output = StringIO()
        with redirect_stdout(output):
            code = main([str(self.root), "--format", "json"])
        report = json.loads(output.getvalue())
        self.assertEqual(code, 1)
        self.assertEqual(report["summary"]["errors"], 2)
        self.assertEqual(report["summary"]["references_checked"], 2)


if __name__ == "__main__":
    unittest.main()
