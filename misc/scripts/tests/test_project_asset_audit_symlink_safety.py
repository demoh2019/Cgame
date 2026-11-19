#!/usr/bin/env python3
"""Safety regressions for Godot project resource preflight auditing."""

from __future__ import annotations

from contextlib import redirect_stderr
from io import StringIO
from pathlib import Path
from unittest.mock import patch
import os
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import project_asset_audit as audit  # noqa: E402


@unittest.skipUnless(hasattr(os, "symlink"), "requires symlink support")
class SymlinkResourceAuditTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.base = Path(temp.name)
        self.project = self.base / "game"
        self.project.mkdir()

    def write(self, name, data=""):
        path = self.project / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(data, encoding="utf-8")
        return path

    def link(self, name, target, directory=False):
        path = self.project / name
        try:
            path.symlink_to(target, target_is_directory=directory)
        except OSError as exc:
            self.skipTest(f"Host does not permit creating symlinks: {exc}")
        return path

    def codes(self):
        return [finding.code for finding in audit.scan_project(self.project).findings]

    def test_external_file_link_is_rejected_as_resource(self):
        external = self.base / "private.tres"
        external.write_text("private", encoding="utf-8")
        self.link("shared.tres", external)
        self.write("main.gd", 'var x = preload("res://shared.tres")')
        result = audit.scan_project(self.project)
        self.assertIn("EXTERNAL_SYMLINK", [f.code for f in result.findings])
        self.assertIn("RESOURCE_OUTSIDE_PROJECT", [f.code for f in result.findings])

    def test_external_directory_link_is_rejected_as_resource(self):
        outside = self.base / "external"
        outside.mkdir()
        (outside / "secret.tres").write_text("private", encoding="utf-8")
        self.link("assets", outside, directory=True)
        self.write("main.gd", 'load("res://assets/secret.tres")')
        self.assertIn("RESOURCE_OUTSIDE_PROJECT", self.codes())

    def test_internal_file_link_remains_accessible(self):
        source = self.write("assets/inside.tres", "valid")
        self.link("alias.tres", source)
        self.write("main.gd", 'load("res://alias.tres")')
        self.assertNotIn("RESOURCE_OUTSIDE_PROJECT", self.codes())
        self.assertNotIn("UNRESOLVABLE_RESOURCE", self.codes())

    def test_internal_directory_link_remains_accessible(self):
        self.write("assets/item.tres", "valid")
        self.link("short", self.project / "assets", directory=True)
        self.write("main.gd", 'preload("res://short/item.tres")')
        self.assertNotIn("RESOURCE_OUTSIDE_PROJECT", self.codes())
        self.assertNotIn("MISSING_RESOURCE", self.codes())

    def test_dangling_file_link_not_misreported_as_case_mismatch(self):
        self.link("missing.tres", self.project / "not-created.tres")
        self.write("main.gd", 'load("res://missing.tres")')
        codes = self.codes()
        self.assertIn("UNRESOLVABLE_SYMLINK", codes)
        self.assertIn("MISSING_RESOURCE", codes)
        self.assertNotIn("CASE_MISMATCH", codes)

    def test_self_referential_link_cannot_crash_scan(self):
        self.link("loop.tres", "loop.tres")
        self.write("main.gd", 'load("res://loop.tres")')
        codes = self.codes()
        self.assertIn("UNRESOLVABLE_SYMLINK", codes)
        self.assertIn("UNRESOLVABLE_RESOURCE", codes)

    def test_two_link_cycle_cannot_crash_scan(self):
        self.link("first.tres", "second.tres")
        self.link("second.tres", "first.tres")
        self.write("main.gd", 'load("res://first.tres")')
        codes = self.codes()
        self.assertEqual(codes.count("UNRESOLVABLE_SYMLINK"), 2)
        self.assertIn("UNRESOLVABLE_RESOURCE", codes)

    def test_parent_directory_symlink_cycle_cannot_crash(self):
        self.link("cycle", "cycle", directory=True)
        self.write("main.gd", 'load("res://cycle/resource.tres")')
        self.assertIn("UNRESOLVABLE_RESOURCE", self.codes())

    def test_case_mismatch_still_reported_for_existing_asset(self):
        self.write("Known.tres", "valid")
        self.write("main.gd", 'load("res://known.tres")')
        self.assertIn("CASE_MISMATCH", self.codes())


class ScanFailureTests(unittest.TestCase):
    @staticmethod
    def inaccessible_walk(*args, **kwargs):
        callback = kwargs["onerror"]
        callback(PermissionError("nested project folder is inaccessible"))
        yield None

    def test_unreadable_subtree_cannot_return_success(self):
        with tempfile.TemporaryDirectory() as project:
            with patch.object(audit.os, "walk", self.inaccessible_walk):
                with self.assertRaisesRegex(ValueError, "Cannot enumerate"):
                    audit.scan_project(Path(project))

    def test_cli_returns_configuration_error_for_unreadable_subtree(self):
        with tempfile.TemporaryDirectory() as project:
            with patch.object(audit.os, "walk", self.inaccessible_walk):
                with redirect_stderr(StringIO()):
                    code = audit.main([project])
                self.assertEqual(code, 2)

    def test_existing_normal_scan_still_works(self):
        with tempfile.TemporaryDirectory() as project:
            path = Path(project)
            (path / "valid.tres").write_text("valid", encoding="utf-8")
            (path / "main.gd").write_text('preload("res://valid.tres")', encoding="utf-8")
            report = audit.scan_project(path)
            self.assertEqual(report.errors, 0)
            self.assertEqual(report.references_checked, 1)


if __name__ == "__main__":
    unittest.main()
