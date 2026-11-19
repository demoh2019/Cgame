"""Tests for the opt-in Godot project snapshot and headless smoke checker."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import ai_project_smoke as smoke


class SmokeTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.project = self.root / "game"
        self.project.mkdir()
        self.file("project.godot", b"config_version=5\n")

    def file(self, path, content=b"data"):
        target = self.project / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(content)
        return target

    def snapshot(self, **kwargs):
        target = self.root / "snapshot"
        return smoke.snapshot_project(self.project, target, **kwargs)

    def fake_godot(self, code="print('Godot fake imported')"):
        # Linux CI regression: simulate a Godot binary without installing the engine.
        file = self.root / "godot-fake"
        file.write_text("#!/usr/bin/env python3\n" + code + "\n", encoding="utf-8")
        file.chmod(0o755)
        return str(file)

    def cli(self, *args):
        return subprocess.run([sys.executable, smoke.__file__, str(self.project), *args],
                              capture_output=True, text=True)

    def test_snapshot_files_and_binary_bytes(self):
        self.file("textures/data.bin", b"\x00\xff\x12")
        self.assertEqual(self.snapshot(), {"files": 2, "bytes": 20})
        self.assertEqual((self.root / "snapshot/textures/data.bin").read_bytes(), b"\x00\xff\x12")

    def test_snapshot_ignores_import_cache(self):
        for name in smoke.SKIP_DIRS:
            self.file(name + "/cache", b"lots of bytes")
        self.assertEqual(self.snapshot()["files"], 1)

    def test_empty_or_missing_project(self):
        (self.project / "project.godot").unlink()
        with self.assertRaisesRegex(smoke.SmokeError, "project.godot"):
            self.snapshot()

    def test_snapshot_refuses_missing_root(self):
        with self.assertRaises(smoke.SmokeError):
            smoke.snapshot_project(self.root / "absent", self.root / "copied")

    def test_snapshot_refuses_nested_target(self):
        with self.assertRaisesRegex(smoke.SmokeError, "outside"):
            smoke.snapshot_project(self.project, self.project / "copy")

    def test_snapshot_refuses_parent_target(self):
        with self.assertRaisesRegex(smoke.SmokeError, "outside"):
            smoke.snapshot_project(self.project, self.root)

    def test_snapshot_exact_byte_limit_allowed(self):
        self.assertEqual(self.snapshot(max_bytes=17)["bytes"], 17)

    def test_snapshot_byte_limit_rejected(self):
        self.file("big", b"abc")
        with self.assertRaisesRegex(smoke.SmokeError, "budget"):
            self.snapshot(max_bytes=19)

    def test_snapshot_exact_file_limit_allowed(self):
        self.file("other")
        self.assertEqual(self.snapshot(max_files=2)["files"], 2)

    def test_snapshot_file_limit_rejected(self):
        self.file("another")
        with self.assertRaisesRegex(smoke.SmokeError, "budget"):
            self.snapshot(max_files=1)

    def test_negative_budgets_rejected(self):
        for kwargs in ({"max_files": -1}, {"max_files": 0}, {"max_bytes": -1}):
            with self.subTest(kwargs=kwargs), self.assertRaises(smoke.SmokeError):
                self.snapshot(**kwargs)

    def test_symbolic_file_rejected(self):
        original = self.file("original")
        try:
            (self.project / "link").symlink_to(original)
        except OSError:
            self.skipTest("symlinks not supported")
        with self.assertRaisesRegex(smoke.SmokeError, "symlink"):
            self.snapshot()

    def test_symbolic_directory_rejected(self):
        directory = self.project / "assets"
        directory.mkdir()
        try:
            (self.project / "outside").symlink_to(directory, target_is_directory=True)
        except OSError:
            self.skipTest("symlinks not supported")
        with self.assertRaisesRegex(smoke.SmokeError, "symlink"):
            self.snapshot()

    def test_symbolic_root_rejected(self):
        link = self.root / "link"
        try:
            link.symlink_to(self.project, target_is_directory=True)
        except OSError:
            self.skipTest("symlinks not supported")
        with self.assertRaises(smoke.SmokeError):
            smoke.snapshot_project(link, self.root / "output")

    def test_named_pipe_rejected(self):
        if not hasattr(os, "mkfifo"):
            self.skipTest("mkfifo not available")
        os.mkfifo(self.project / "pipe")
        with self.assertRaises(smoke.SmokeError):
            self.snapshot()

    def test_unicode_paths(self):
        self.file("декорации/雪.gd", b"data")
        self.snapshot()
        self.assertTrue((self.root / "snapshot/декорации/雪.gd").exists())

    def test_walk_failures_not_silent(self):
        def broken_walk(*args, **kwargs):
            kwargs["onerror"](PermissionError("denied"))
            yield str(self.project), [], []
        with patch.object(smoke.os, "walk", side_effect=broken_walk):
            with self.assertRaises(smoke.SmokeError):
                self.snapshot()

    def test_error_and_warning_detection(self):
        errs, warnings = smoke._diagnostics("SCRIPT ERROR: bad\nWARNING: suspicious\nERROR: failed\n", self.project)
        self.assertEqual(len(errs), 2)
        self.assertEqual(len(warnings), 1)

    def test_diagnostic_count_bounded(self):
        text = "ERROR: fail\n" * 100
        self.assertEqual(len(smoke._diagnostics(text, self.project)[0]), smoke.MAX_DIAGNOSTICS)

    def test_stage_path_redacted(self):
        errs, _ = smoke._diagnostics("ERROR: " + str(self.project) + "/scene.gd", self.project)
        self.assertIn("<STAGED_PROJECT>/scene.gd", errs[0])

    def test_sample_log_truncates_with_tail(self):
        with tempfile.TemporaryFile(mode="w+b") as file:
            file.write(b"START" + b"a" * 100 + b"ERROR: end\n")
            text, clipped = smoke._sample_output(file, 40)
        self.assertTrue(clipped)
        self.assertIn("START", text)
        self.assertIn("ERROR: end", text)

    @unittest.skipIf(os.name == "nt", "fake executable requires POSIX shebang")
    def test_import_succeeds(self):
        result = smoke.check_project(self.project, godot=self.fake_godot())
        self.assertTrue(result["ok"])
        self.assertEqual([check["name"] for check in result["checks"]], ["import"])

    @unittest.skipIf(os.name == "nt", "fake executable requires POSIX shebang")
    def test_game_only_with_opt_in(self):
        exe = self.fake_godot("import sys\nprint('MODE: import' if '--import' in sys.argv else 'MODE: game')")
        result = smoke.check_project(self.project, godot=exe, run_game=True)
        self.assertTrue(result["ok"])
        self.assertEqual([check["name"] for check in result["checks"]], ["import", "game"])

    @unittest.skipIf(os.name == "nt", "fake executable requires POSIX shebang")
    def test_godot_return_zero_but_error_log_fails(self):
        result = smoke.check_project(self.project, godot=self.fake_godot("print('SCRIPT ERROR: parser failure')"))
        self.assertFalse(result["ok"])
        self.assertEqual(result["checks"][0]["errors"], ["SCRIPT ERROR: parser failure"])

    @unittest.skipIf(os.name == "nt", "fake executable requires POSIX shebang")
    def test_nonzero_exit_fails(self):
        result = smoke.check_project(self.project, godot=self.fake_godot("raise SystemExit(4)"))
        self.assertFalse(result["ok"])
        self.assertEqual(result["checks"][0]["exit_code"], 4)

    @unittest.skipIf(os.name == "nt", "fake executable requires POSIX shebang")
    def test_game_not_run_if_import_failed(self):
        exe = self.fake_godot("import sys\nprint('ERROR: import failed') if '--import' in sys.argv else print('game started')")
        result = smoke.check_project(self.project, godot=exe, run_game=True)
        self.assertEqual(len(result["checks"]), 1)

    @unittest.skipIf(os.name == "nt", "fake executable requires POSIX shebang")
    def test_timeout_is_reported(self):
        result = smoke.check_project(self.project, godot=self.fake_godot("import time\ntime.sleep(2)"), timeout=0.05)
        self.assertFalse(result["ok"])
        self.assertTrue(result["checks"][0]["timed_out"])

    @unittest.skipIf(os.name == "nt", "fake executable requires POSIX shebang")
    def test_does_not_inherit_api_key_environment(self):
        exe = self.fake_godot("import os\nprint('ERROR: inherited secret') if 'OPENAI_API_KEY' in os.environ else print('clean')")
        with patch.dict(os.environ, {"OPENAI_API_KEY": "never-pass-this"}):
            self.assertTrue(smoke.check_project(self.project, godot=exe)["ok"])

    @unittest.skipIf(os.name == "nt", "fake executable requires POSIX shebang")
    def test_original_project_remains_unchanged(self):
        exe = self.fake_godot("from pathlib import Path\nimport sys\np=Path(sys.argv[sys.argv.index('--path')+1]);(p/'new.txt').write_text('created')")
        result = smoke.check_project(self.project, godot=exe)
        self.assertTrue(result["ok"])
        self.assertFalse((self.project / "new.txt").exists())

    def test_invalid_timeout_rejected(self):
        for value in (-1, 0, 601):
            with self.subTest(timeout=value), self.assertRaises(smoke.SmokeError):
                smoke.check_project(self.project, godot="anything", timeout=value)

    def test_unavailable_executable_rejected(self):
        with self.assertRaises(smoke.SmokeError):
            smoke.check_project(self.project, godot="no-such-godot-binary-___")

    def test_cli_requires_consent(self):
        result = self.cli()
        self.assertEqual(result.returncode, 2)
        self.assertIn("--approve-execution", result.stderr)

    @unittest.skipIf(os.name == "nt", "fake executable requires POSIX shebang")
    def test_cli_success_json(self):
        result = self.cli("--godot", self.fake_godot(), "--approve-execution")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(json.loads(result.stdout)["ok"])

    @unittest.skipIf(os.name == "nt", "fake executable requires POSIX shebang")
    def test_cli_error_status_one(self):
        result = self.cli("--godot", self.fake_godot("print('ERROR: broken scene')"), "--approve-execution")
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertFalse(json.loads(result.stdout)["ok"])

    def test_cli_missing_godot_status_two(self):
        result = self.cli("--godot", "no-such-godot-binary-___", "--approve-execution")
        self.assertEqual(result.returncode, 2)


    @unittest.skipIf(os.name == "nt", "fake executable requires POSIX shebang")
    def test_middle_error_not_hidden_by_head_tail_log_sampling(self):
        exe = self.fake_godot(
            "print('HEAD')\nprint('x' * 70000)\nprint('ERROR: hidden parser failure')"
            "\nprint('y' * 70000)\nprint('TAIL')")
        report = smoke.check_project(self.project, godot=exe)
        check = report["checks"][0]
        self.assertFalse(report["ok"])
        self.assertFalse(check["ok"])
        self.assertTrue(check["output_truncated"])
        self.assertEqual(check["error_count"], 1)
        self.assertEqual(check["errors"], ["ERROR: hidden parser failure"])

    @unittest.skipIf(os.name == "nt", "fake executable requires POSIX shebang")
    def test_middle_warning_reported_without_failing_check(self):
        exe = self.fake_godot(
            "print('x' * 70000)\nprint('WARNING: hidden deprecation')"
            "\nprint('y' * 70000)")
        report = smoke.check_project(self.project, godot=exe)
        check = report["checks"][0]
        self.assertTrue(report["ok"])
        self.assertEqual(check["warning_count"], 1)
        self.assertEqual(check["warnings"], ["WARNING: hidden deprecation"])

    @unittest.skipIf(os.name == "nt", "fake executable requires POSIX shebang")
    def test_many_hidden_errors_still_mark_result_failed(self):
        exe = self.fake_godot("print('ERROR: repeated\\n' * 100, end='')")
        check = smoke.check_project(self.project, godot=exe)["checks"][0]
        self.assertFalse(check["ok"])
        self.assertEqual(check["error_count"], 100)
        self.assertEqual(len(check["errors"]), smoke.MAX_DIAGNOSTICS)
        self.assertTrue(check["diagnostics_truncated"])

    def test_full_log_diagnostics_empty(self):
        with tempfile.TemporaryFile(mode="w+b") as log:
            self.assertEqual(smoke._scan_log_diagnostics(log, self.project),
                             ([], [], 0, 0))

    def test_full_log_diagnostics_crlf_and_invalid_utf8(self):
        with tempfile.TemporaryFile(mode="w+b") as log:
            log.write(b"NOTICE: first\r\nERROR: broken\xff\r\nWARNING: suspect\r\n")
            errors, warnings, error_count, warning_count = smoke._scan_log_diagnostics(log, self.project)
        self.assertEqual(error_count, 1)
        self.assertEqual(warning_count, 1)
        self.assertEqual(len(errors), 1)
        self.assertIn("broken", errors[0])
        self.assertEqual(warnings, ["WARNING: suspect"])

    def test_full_log_diagnostics_drops_huge_line_tail(self):
        with tempfile.TemporaryFile(mode="w+b") as log:
            log.write(b"ERROR: start" + b"A" * (2 * 1024 * 1024) + b"\nWARNING: after\n")
            errors, warnings, ec, wc = smoke._scan_log_diagnostics(log, self.project)
        self.assertEqual((ec, wc), (1, 1))
        self.assertEqual(len(errors[0]), 500)
        self.assertEqual(warnings, ["WARNING: after"])

    def test_full_log_diagnostics_redacts_stage_path(self):
        with tempfile.TemporaryFile(mode="w+b") as log:
            log.write(("ERROR: " + str(self.project) + "/main.gd\n").encode("utf-8"))
            errors, _, ec, _ = smoke._scan_log_diagnostics(log, self.project)
        self.assertEqual(ec, 1)
        self.assertEqual(errors, ["ERROR: <STAGED_PROJECT>/main.gd"])

    def test_full_log_diagnostics_counts_warnings_past_reporting_cap(self):
        with tempfile.TemporaryFile(mode="w+b") as log:
            log.write(b"WARNING: x\n" * 101)
            errors, warnings, ec, wc = smoke._scan_log_diagnostics(log, self.project)
        self.assertEqual(errors, [])
        self.assertEqual(ec, 0)
        self.assertEqual(wc, 101)
        self.assertEqual(len(warnings), smoke.MAX_DIAGNOSTICS)

    @unittest.skipIf(os.name == "nt", "fake executable requires POSIX shebang")
    def test_report_includes_diagnostic_counts_when_no_errors(self):
        report = smoke.check_project(self.project, godot=self.fake_godot("print('ready')"))
        check = report["checks"][0]
        self.assertTrue(check["ok"])
        self.assertEqual(check["error_count"], 0)
        self.assertEqual(check["warning_count"], 0)
        self.assertFalse(check["diagnostics_truncated"])




    @unittest.skipIf(os.name == "nt", "fake executable requires POSIX shebang")
    def test_structured_inline_error_has_resource_and_line(self):
        exe = self.fake_godot("print('ERROR: res://ai_generated/scenes/main.tscn:18 - Invalid node')")
        report = smoke.check_project(self.project, godot=exe)
        self.assertFalse(report["ok"])
        stage = report["checks"][0]
        self.assertEqual(stage["error_count"], 1)
        self.assertEqual(stage["diagnostics"][0]["resource"], "res://ai_generated/scenes/main.tscn")
        self.assertEqual(stage["diagnostics"][0]["line"], 18)
        self.assertEqual(stage["diagnostics"][0]["severity"], "error")
        json.dumps(report)

    @unittest.skipIf(os.name == "nt", "fake executable requires POSIX shebang")
    def test_structured_multiline_script_diagnostic_for_repair(self):
        exe = self.fake_godot(
            "print('SCRIPT ERROR: Parse Error: Unexpected token')\n"
            "print(' at: GDScript::reload (res://ai_generated/scripts/hero.gd:27)')")
        report = smoke.check_project(self.project, godot=exe)
        self.assertFalse(report["ok"])
        self.assertEqual(report["checks"][0]["diagnostics"][0]["resource"], "res://ai_generated/scripts/hero.gd")
        self.assertEqual(report["checks"][0]["diagnostics"][0]["line"], 27)

    @unittest.skipIf(os.name == "nt", "fake executable requires POSIX shebang")
    def test_structured_warning_never_fails_smoke(self):
        exe = self.fake_godot("print('WARNING: res://visuals/effect.gdshader:9 shader warning')")
        report = smoke.check_project(self.project, godot=exe)
        self.assertTrue(report["ok"])
        self.assertEqual(report["checks"][0]["warning_count"], 1)
        self.assertEqual(report["checks"][0]["diagnostics"][0]["severity"], "warning")
        self.assertEqual(report["checks"][0]["diagnostics"][0]["line"], 9)

    @unittest.skipIf(os.name == "nt", "fake executable requires POSIX shebang")
    def test_structured_middle_error_found_in_oversized_log(self):
        exe = self.fake_godot(
            "print('normal output\\n' * 12000)\n"
            "print('ERROR: res://ai_generated/scripts/main.gd:52 parse error')\n"
            "print('normal output\\n' * 12000)")
        report = smoke.check_project(self.project, godot=exe)
        self.assertFalse(report["ok"])
        stage = report["checks"][0]
        self.assertTrue(stage["output_truncated"])
        self.assertEqual(stage["error_count"], 1)
        self.assertEqual(stage["diagnostics"][0]["line"], 52)

    @unittest.skipIf(os.name == "nt", "fake executable requires POSIX shebang")
    def test_diagnostic_cap_preserves_total_count(self):
        exe = self.fake_godot("print('ERROR: repeated\\n' * 100)")
        report = smoke.check_project(self.project, godot=exe)
        stage = report["checks"][0]
        self.assertEqual(stage["error_count"], 100)
        self.assertEqual(len(stage["errors"]), smoke.MAX_DIAGNOSTICS)
        self.assertEqual(len(stage["diagnostics"]), smoke.MAX_DIAGNOSTICS)
        self.assertTrue(stage["diagnostics_truncated"])

    @unittest.skipIf(os.name == "nt", "fake executable requires POSIX shebang")
    def test_structured_error_does_not_include_staging_directory(self):
        exe = self.fake_godot(
            "import sys\n"
            "print('ERROR: ' + sys.argv[sys.argv.index('--path')+1] + '/secret.gd unavailable')")
        report = smoke.check_project(self.project, godot=exe)
        self.assertFalse(report["ok"])
        raw = json.dumps(report, ensure_ascii=False)
        self.assertIn("<STAGED_PROJECT>/secret.gd", raw)
        self.assertNotIn("godot-ai-smoke-", raw)

if __name__ == "__main__":
    unittest.main()
