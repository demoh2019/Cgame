#!/usr/bin/env python3
"""Regression tests for secure GitHub Actions resource audit annotations."""

from __future__ import annotations

from contextlib import redirect_stdout
from io import StringIO
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import project_asset_audit as audit  # noqa: E402


class GitHubAnnotationTests(unittest.TestCase):
    def test_annotation_error_includes_file_and_line(self):
        finding = audit.Finding("error", "MISSING_RESOURCE", "main.gd", 3, "Missing", "res://gone.tres")
        self.assertEqual(audit._format_github_finding(finding),
                         "::error file=main.gd,line=3,title=MISSING_RESOURCE::Missing [res://gone.tres]")

    def test_annotation_warning_has_no_line_zero(self):
        finding = audit.Finding("warning", "DEPENDENCY_CYCLE", "a.gd", 0, "Cycle")
        self.assertEqual(audit._format_github_finding(finding),
                         "::warning file=a.gd,title=DEPENDENCY_CYCLE::Cycle")

    def test_escape_property_special_characters(self):
        self.assertEqual(audit._escape_github_property("x%:,\r\n"), "x%25%3A%2C%0D%0A")

    def test_escape_data_special_characters(self):
        self.assertEqual(audit._escape_github_data("x%\r\ny"), "x%25%0D%0Ay")

    def test_filename_command_injection_not_possible(self):
        f = audit.Finding("error", "X", "a.gd\n::warning file=hacked.gd", 1, "msg")
        output = audit._format_github_finding(f)
        self.assertIn("%0A%3A%3Awarning", output)
        self.assertNotIn("\n", output)

    def test_message_command_injection_not_possible(self):
        f = audit.Finding("error", "X", "a.gd", 1, "msg\n::warning file=hacked.gd")
        output = audit._format_github_finding(f)
        self.assertIn("msg%0A::warning", output)
        self.assertNotIn("\n", output)

    def test_reference_percent_and_linebreak_escaped(self):
        f = audit.Finding("error", "X", "a.gd", 1, "msg", "res://bad%\nname")
        self.assertIn("[res://bad%25%0Aname]", audit._format_github_finding(f))

    def test_unicode_filename_preserved(self):
        f = audit.Finding("error", "X", "café/雪.gd", 1, "msg")
        self.assertIn("café/雪.gd", audit._format_github_finding(f))


class GitHubCLITests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)

    def write(self, name, text):
        p = self.root / name
        p.write_text(text, encoding="utf-8")

    def run_cli(self, *args):
        with redirect_stdout(StringIO()) as output:
            code = audit.main([str(self.root), "--format", "github", *args])
        return code, output.getvalue()

    def test_missing_asset_emits_error_annotation(self):
        self.write("main.gd", 'preload("res://gone.tres")')
        code, result = self.run_cli()
        self.assertEqual(code, 1)
        self.assertIn("::error file=main.gd,line=1,title=MISSING_RESOURCE::", result)

    def test_cycle_emits_warning_but_returns_success(self):
        self.write("main.gd", 'preload("res://main.gd")')
        code, result = self.run_cli()
        self.assertEqual(code, 0)
        self.assertIn("::warning file=main.gd,title=DEPENDENCY_CYCLE::", result)

    def test_fail_on_warning_returns_one(self):
        self.write("main.gd", 'load("res://main.gd")')
        self.assertEqual(self.run_cli("--fail-on-warning")[0], 1)

    def test_no_cycles_suppresses_cycle_warning(self):
        self.write("main.gd", 'load("res://main.gd")')
        code, result = self.run_cli("--no-cycles", "--fail-on-warning")
        self.assertEqual(code, 0)
        self.assertNotIn("::warning", result)

    def test_clean_project_outputs_summary_only(self):
        self.write("main.gd", "extends Node")
        code, result = self.run_cli()
        self.assertEqual(code, 0)
        self.assertNotIn("::error", result)
        self.assertIn("0 errors, 0 warnings", result)

    def test_annotations_sorted_by_filename(self):
        self.write("z.gd", 'preload("res://lost_z.tres")')
        self.write("a.gd", 'preload("res://lost_a.tres")')
        code, result = self.run_cli()
        errors = [s for s in result.splitlines() if s.startswith("::error")]
        self.assertEqual(code, 1)
        self.assertEqual(len(errors), 2)
        self.assertIn("file=a.gd", errors[0])
        self.assertIn("file=z.gd", errors[1])


if __name__ == "__main__":
    unittest.main()
