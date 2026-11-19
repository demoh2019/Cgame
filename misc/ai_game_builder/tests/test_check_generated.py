"""Unit tests for the standalone Godot game verification command."""
import importlib.util
import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

SCRIPT = Path(__file__).resolve().parents[1] / "tools" / "check_generated.py"
spec = importlib.util.spec_from_file_location("check_generated", SCRIPT)
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


class CheckerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.project = Path(self.temp.name) / "game"
        self.project.mkdir()
        (self.project / "project.godot").write_text("config_version=5\n", encoding="utf-8")
        self.generated = self.project / "ai_generated"
        self.generated.mkdir()

    def test_discover_sorted_scripts_nested(self):
        (self.generated / "z.gd").write_text("extends Node\n")
        (self.generated / "a.gd").write_text("extends Node\n")
        (self.generated / "scene.tscn").write_text("[gd_scene format=3]\n")
        (self.generated / "nested").mkdir()
        (self.generated / "nested" / "b.gd").write_text("extends Node\n")
        self.assertEqual(checker.discover_scripts(self.project), [
            "res://ai_generated/a.gd", "res://ai_generated/nested/b.gd", "res://ai_generated/z.gd"])

    def test_missing_generated_dir(self):
        self.generated.rmdir()
        with self.assertRaises(FileNotFoundError):
            checker.discover_scripts(self.project)

    def test_max_file_limit(self):
        for i in range(3):
            (self.generated / f"f{i}.gd").write_text("extends Node\n")
        with self.assertRaisesRegex(ValueError, "More than 2 scripts"):
            checker.discover_scripts(self.project, 2)

    def test_symlink_escapes_are_ignored(self):
        outside = Path(self.temp.name) / "outside.gd"
        outside.write_text("extends Node\n")
        try:
            (self.generated / "bad.gd").symlink_to(outside)
        except (OSError, NotImplementedError):
            self.skipTest("symlinks not supported")
        self.assertEqual(checker.discover_scripts(self.project), [])

    def test_generated_directory_symlink_is_blocked(self):
        self.generated.rmdir()
        outside = Path(self.temp.name) / "outside"
        outside.mkdir()
        try:
            self.generated.symlink_to(outside, target_is_directory=True)
        except (OSError, NotImplementedError):
            self.skipTest("symlinks not supported")
        with self.assertRaisesRegex(ValueError, "outside the project"):
            checker.discover_scripts(self.project)

    def test_script_command_is_parse_only(self):
        command = checker.script_command("godot4", self.project, "res://ai_generated/a.gd")
        self.assertEqual(command, ["godot4", "--headless", "--path", str(self.project),
                                   "--check-only", "--script", "res://ai_generated/a.gd"])
        self.assertNotIn("--editor", command)

    def test_smoke_command_is_explicit(self):
        self.assertEqual(checker.smoke_command("godot4", self.project)[-4:],
                         ["--scene", checker.MAIN_SCENE, "--quit-after", "3"])

    @patch.object(checker.subprocess, "run")
    def test_successful_check(self, mocked):
        mocked.return_value = Mock(stdout="ok", stderr="", returncode=0)
        result = checker.run_check("gdscript_parse", "res://x.gd", ["godot4"], 30)
        self.assertTrue(result["ok"])
        self.assertEqual(result["exit_code"], 0)
        mocked.assert_called_once()
        self.assertFalse(mocked.call_args.kwargs["check"])

    @patch.object(checker.subprocess, "run")
    def test_parser_error_even_on_zero_exit(self, mocked):
        mocked.return_value = Mock(stdout="SCRIPT ERROR: Parse Error: invalid", stderr="", returncode=0)
        self.assertFalse(checker.run_check("parse", "res://x.gd", ["godot4"], 30)["ok"])

    @patch.object(checker.subprocess, "run")
    def test_nonzero_exit(self, mocked):
        mocked.return_value = Mock(stdout="", stderr="failure", returncode=1)
        self.assertFalse(checker.run_check("parse", "res://x.gd", ["godot4"], 30)["ok"])

    @patch.object(checker.subprocess, "run")
    def test_timeout(self, mocked):
        mocked.side_effect = subprocess.TimeoutExpired(cmd=["godot4"], timeout=2)
        self.assertIn("timeout", checker.run_check("parse", "res://x.gd", ["godot4"], 2)["output"])

    @patch.object(checker.subprocess, "run")
    def test_binary_missing(self, mocked):
        mocked.side_effect = FileNotFoundError("godot4")
        self.assertIn("Could not start", checker.run_check("parse", "res://x.gd", ["godot4"], 2)["output"])

    @patch.object(checker, "run_check")
    def test_evaluate_parse_only_default(self, mocked):
        (self.generated / "a.gd").write_text("extends Node\n")
        mocked.return_value = {"ok": True, "path": "res://ai_generated/a.gd", "output": ""}
        report = checker.evaluate("godot4", self.project)
        self.assertEqual(report["summary"], {"total": 1, "passed": 1, "failed": 0})
        self.assertEqual(mocked.call_count, 1)
        self.assertIn("--check-only", mocked.call_args.args[2])

    @patch.object(checker, "run_check")
    def test_smoke_run_missing_main(self, mocked):
        report = checker.evaluate("godot4", self.project, smoke_run=True)
        self.assertEqual(report["summary"], {"total": 1, "passed": 0, "failed": 1})
        mocked.assert_not_called()

    @patch.object(checker, "run_check")
    def test_smoke_run_requires_flag(self, mocked):
        (self.generated / "main.tscn").write_text("[gd_scene format=3]\n")
        checker.evaluate("godot4", self.project)
        mocked.assert_not_called()
        mocked.return_value = {"ok": True, "path": checker.MAIN_SCENE, "output": ""}
        checker.evaluate("godot4", self.project, smoke_run=True)
        self.assertEqual(mocked.call_args.args[0], "scene_smoke")

    def test_invalid_project(self):
        (self.project / "project.godot").unlink()
        with self.assertRaises(FileNotFoundError):
            checker.evaluate("godot4", self.project)

    def test_invalid_limits(self):
        for t in (0, 121):
            with self.assertRaises(ValueError):
                checker.evaluate("godot4", self.project, timeout=t)
        for files in (0, 2001):
            with self.assertRaises(ValueError):
                checker.evaluate("godot4", self.project, max_files=files)

    @patch.object(checker, "run_check")
    def test_report_written_and_return_code(self, mocked):
        (self.generated / "bad.gd").write_text("???")
        mocked.return_value = {"ok": False, "path": "res://ai_generated/bad.gd", "output": "parse failure"}
        report_path = Path(self.temp.name) / "reports" / "diagnostics.json"
        code = checker.main(["--godot", "fake", "--project", str(self.project), "--report", str(report_path)])
        self.assertEqual(code, 1)
        doc = json.loads(report_path.read_text())
        self.assertEqual(doc["summary"]["failed"], 1)

    def test_usage_error_return_code(self):
        code = checker.main(["--project", str(self.project / "missing")])
        self.assertEqual(code, 2)


if __name__ == "__main__":
    unittest.main()
