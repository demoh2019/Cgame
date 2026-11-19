"""Pure, offline tests for opt-in AI repair diagnostics and source excerpts."""

import contextlib
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import ai_repair_context as repair


class RepairContextTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.write("project.godot", "config_version=5\n")

    def write(self, name, content):
        p = self.root / name
        p.parent.mkdir(parents=True, exist_ok=True)
        if isinstance(content, bytes):
            p.write_bytes(content)
        else:
            p.write_text(content, encoding="utf-8")
        return p

    def report(self, message="SCRIPT ERROR: Parse Error: res://code/player.gd:3 bad"):
        return {"format": 1, "ok": False, "checks": [
            {"name": "import", "ok": False, "errors": [message], "warnings": [],
             "error_count": 1, "warning_count": 0}]}

    def context(self, report=None, allow=()):
        return repair.build_context(self.report() if report is None else report, self.root, allow)

    def test_default_is_metadata_only(self):
        self.write("code/player.gd", "secret = 'do-not-share'\npass\ninvalid\n")
        result = self.context()
        self.assertTrue(result["requires_approval"])
        self.assertTrue(result["diagnostics_untrusted"])
        self.assertFalse(result["source_opt_in"])
        self.assertNotIn("do-not-share", json.dumps(result))
        self.assertNotIn("source_excerpt", result["hints"][0])

    def test_parse_error_path_and_line(self):
        hint = self.context()["hints"][0]
        self.assertEqual((hint["kind"], hint["path"], hint["line"]),
                         ("syntax", "res://code/player.gd", 3))

    def test_absolute_staged_path_is_normalized(self):
        hint = self.context(self.report("ERROR: <STAGED_PROJECT>/scenes/main.tscn:20 bad"))["hints"][0]
        self.assertEqual((hint["path"], hint["line"]), ("res://scenes/main.tscn", 20))

    def test_source_excerpt_requires_exact_allowlist(self):
        self.write("code/player.gd", "line1\nline2\nline3\nline4\nline5\nline6\n")
        hint = self.context(allow=("res://code/player.gd",))["hints"][0]
        self.assertEqual(hint["source_excerpt"],
                         {"line_start": 1, "line_end": 5,
                          "text": "1: line1\n2: line2\n3: line3\n4: line4\n5: line5"})

    def test_unrelated_allowed_source_not_included(self):
        self.write("other.gd", "secret\n")
        result = self.context(allow=("res://other.gd",))
        self.assertNotIn("source_excerpt", result["hints"][0])

    def test_missing_file_no_excerpt(self):
        hint = self.context(allow=("res://code/player.gd",))["hints"][0]
        self.assertNotIn("source_excerpt", hint)

    def test_too_large_source_no_excerpt(self):
        self.write("code/player.gd", "x" * (repair.MAX_SOURCE_BYTES + 1))
        self.assertNotIn("source_excerpt", self.context(allow=("res://code/player.gd",))["hints"][0])

    def test_binary_source_no_excerpt(self):
        self.write("code/player.gd", b"aaa\x00bbb\n")
        self.assertNotIn("source_excerpt", self.context(allow=("res://code/player.gd",))["hints"][0])

    def test_invalid_utf8_source_no_excerpt(self):
        self.write("code/player.gd", b"\xff\n")
        self.assertNotIn("source_excerpt", self.context(allow=("res://code/player.gd",))["hints"][0])

    def test_excerpt_output_bounded(self):
        self.write("code/player.gd", "x" * 5000 + "\n" * 4)
        hint = self.context(allow=("res://code/player.gd",))["hints"][0]
        self.assertLessEqual(len(hint["source_excerpt"]["text"]), repair.MAX_EXCERPT_CHARS)

    def test_source_line_outside_file_no_excerpt(self):
        self.write("code/player.gd", "single\n")
        self.assertNotIn("source_excerpt", self.context(allow=("res://code/player.gd",))["hints"][0])

    def test_missing_line_no_excerpt(self):
        self.write("code/player.gd", "single\n")
        hint = self.context(self.report("ERROR: res://code/player.gd failed"),
                            allow=("res://code/player.gd",))["hints"][0]
        self.assertIsNone(hint["line"])
        self.assertNotIn("source_excerpt", hint)

    def test_out_of_project_diagnostic_is_not_a_target(self):
        hint = self.context(self.report("ERROR: res://../secret.gd:1"))["hints"][0]
        self.assertIsNone(hint["path"])

    def test_hidden_diagnostic_is_not_a_target(self):
        hint = self.context(self.report("ERROR: res://.env/private.gd:1"))["hints"][0]
        self.assertIsNone(hint["path"])

    def test_unapproved_nonresource_file_rejected(self):
        for path in ("res://.env", "res://project.godot", "res://dir/../file.gd",
                     "res://script.py", "res:///absolute.gd", "res://back\\slash.gd"):
            with self.subTest(path=path), self.assertRaises(repair.RepairContextError):
                self.context(allow=(path,))

    def test_symlinked_file_rejected(self):
        self.write("real.gd", "line\n")
        try:
            (self.root / "code").mkdir()
            (self.root / "code/player.gd").symlink_to(self.root / "real.gd")
        except (OSError, NotImplementedError):
            self.skipTest("No symlinks")
        with self.assertRaises(repair.RepairContextError):
            self.context(allow=("res://code/player.gd",))

    def test_symlinked_project_root_rejected(self):
        link = self.root.parent / (self.root.name + "-alias")
        try:
            link.symlink_to(self.root, target_is_directory=True)
        except (OSError, NotImplementedError):
            self.skipTest("No symlinks")
        self.addCleanup(lambda: link.unlink(missing_ok=True))
        with self.assertRaises(repair.RepairContextError):
            repair.build_context(self.report(), link)

    def test_allowlist_limit(self):
        with self.assertRaises(repair.RepairContextError):
            self.context(allow=tuple(f"res://{n}.gd" for n in range(5)))

    def test_clean_report_not_eligible(self):
        with self.assertRaisesRegex(repair.RepairContextError, "no repair"):
            self.context({"format": 1, "ok": True, "checks": [{"name": "import", "ok": True,
                          "errors": [], "warnings": []}]})

    def test_inconsistent_failed_report_rejected(self):
        report = {"format": 1, "ok": False, "checks": [
            {"name": "import", "ok": True, "errors": [], "warnings": []}]}
        with self.assertRaisesRegex(repair.RepairContextError, "Inconsistent"):
            self.context(report)

    def test_failed_stage_without_diagnostic_has_fallback(self):
        report = self.report()
        report["checks"][0]["errors"] = []
        report["checks"][0]["error_count"] = 0
        hint = self.context(report)["hints"][0]
        self.assertIsNone(hint["path"])
        self.assertIn("failed", hint["message"])

    def test_warning_does_not_become_repair_hint(self):
        report = self.report()
        report["checks"][0]["warnings"] = ["WARNING: warning"]
        report["checks"][0]["warning_count"] = 1
        result = self.context(report)
        self.assertEqual(result["summary"]["warnings"], 1)
        self.assertEqual(len(result["hints"]), 1)

    def test_counts_are_not_lost_to_hint_budget(self):
        report = self.report()
        report["checks"][0]["errors"] = ["ERROR: failed"] * 50
        report["checks"][0]["error_count"] = 52
        result = self.context(report)
        self.assertEqual(len(result["hints"]), repair.MAX_DIAGNOSTICS)
        self.assertEqual(result["summary"]["errors"], 52)
        self.assertTrue(result["summary"]["truncated"])

    def test_many_stages_still_respect_hint_budget(self):
        report = self.report()
        report["checks"].append({"name": "game", "ok": False,
               "errors": ["ERROR: bad"] * 30, "warnings": [], "error_count": 30})
        report["checks"][0]["errors"] = ["ERROR: bad"] * 30
        report["checks"][0]["error_count"] = 30
        self.assertEqual(len(self.context(report)["hints"]), 30)

    def test_rejects_bad_diagnostic_count(self):
        for value in (-1, "one", True):
            report = self.report()
            report["checks"][0]["error_count"] = value
            with self.subTest(value=value), self.assertRaises(repair.RepairContextError):
                self.context(report)

    def test_rejects_non_string_diagnostics(self):
        report = self.report()
        report["checks"][0]["errors"] = [None]
        with self.assertRaises(repair.RepairContextError):
            self.context(report)

    def test_rejects_invalid_report(self):
        for obj in (None, [], {}, {"ok": False, "format": 3, "checks": []},
                    {"ok": False, "format": 1, "checks": [None]}):
            with self.subTest(obj=obj), self.assertRaises(repair.RepairContextError):
                repair.build_context(obj, self.root)

    def test_missing_project_rejected(self):
        (self.root / "project.godot").unlink()
        with self.assertRaises(repair.RepairContextError):
            self.context()

    def test_categories(self):
        examples = {"ERROR: failed loading resource": "missing_resource",
                    "SCRIPT ERROR: Invalid call": "runtime", "ERROR: import failed": "import",
                    "ERROR: other failure": "other"}
        for message, expected in examples.items():
            with self.subTest(message=message):
                self.assertEqual(self.context(self.report(message))["hints"][0]["kind"], expected)

    def test_deterministic_output(self):
        self.assertEqual(json.dumps(self.context(), sort_keys=True), json.dumps(self.context(), sort_keys=True))

    def test_cli_json(self):
        path = self.write("report.json", json.dumps(self.report()))
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc = repair.main([str(self.root), "--report", str(path)])
        self.assertEqual(rc, 0)
        self.assertEqual(json.loads(buf.getvalue())["schema"], repair.SCHEMA)

    def test_cli_rejects_oversized_json(self):
        path = self.write("report.json", "x" * (repair.MAX_REPORT_BYTES + 1))
        with contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(repair.main([str(self.root), "--report", str(path)]), 2)

    def test_cli_invalid_json(self):
        path = self.write("report.json", "no-json")
        with contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(repair.main([str(self.root), "--report", str(path)]), 2)

    def test_cli_no_automatic_upload_or_execution(self):
        path = self.write("report.json", json.dumps(self.report()))
        with patch("subprocess.run", side_effect=AssertionError("No execution")), \
             patch("urllib.request.urlopen", side_effect=AssertionError("No network")):
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(repair.main([str(self.root), "--report", str(path)]), 0)


if __name__ == "__main__":
    unittest.main()
