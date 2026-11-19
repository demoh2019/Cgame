"""CLI and integration tests for the headless scene smoke runner."""

import json
from pathlib import Path
import os
import subprocess
import sys
import tempfile
import unittest
from unittest import mock
from xml.etree import ElementTree as ET

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import scene_smoke as smoke

TOOL = Path(smoke.__file__).resolve()
STUB = '''#!/usr/bin/env python3
import os
import sys
import time
args = sys.argv[1:]
if '--import' in args:
    if os.environ.get('FAIL_IMPORT') == '1':
        print('ERROR: Failed import', file=sys.stderr)
    sys.exit(0)
scene = args[args.index('--scene') + 1]
if 'broken' in scene:
    print('SCRIPT ERROR: Parse Error: bad script', file=sys.stderr)
if 'exit_fail' in scene:
    sys.exit(3)
if 'timeout' in scene:
    time.sleep(2)
if 'warning' in scene:
    print('WARNING: normal warning', file=sys.stderr)
if 'early_error' in scene:
    print('ERROR: early error', file=sys.stderr)
    print('x' * 10000, file=sys.stderr)
print('Loaded ' + scene)
'''


class SmokeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "project"
        self.root.mkdir()
        (self.root / "project.godot").write_text("config_version=5\n", encoding="utf-8")
        self.stub = Path(self.temp.name) / "fake_godot.py"
        self.stub.write_text(STUB, encoding="utf-8")
        os.chmod(self.stub, 0o755)

    def scene(self, name):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("[gd_scene format=3]\n", encoding="utf-8")
        return path

    def cli(self, *args):
        proc = subprocess.run([sys.executable, str(TOOL), str(self.root), "--godot", str(self.stub), "--format", "json", *args],
                              capture_output=True, text=True)
        report = json.loads(proc.stdout) if proc.stdout else None
        return proc.returncode, report, proc.stderr

    def test_empty_suite(self):
        code, report, _ = self.cli()
        self.assertEqual(code, 0)
        self.assertEqual(report, {"ok": True, "results": []})

    def test_nested_order_and_exclusions(self):
        for name in ("z.tscn", "a/a.scn", "a/b.tscn", ".godot/ignored.tscn"):
            self.scene(name)
        self.assertEqual(smoke.discover_scenes(self.root, ("a/b*",)), ["a/a.scn", "z.tscn"])

    def test_scene_launch_and_warnings(self):
        self.scene("warning.tscn")
        code, report, _ = self.cli("--frames", "5")
        self.assertEqual(code, 0)
        self.assertEqual(report["results"][0]["status"], "pass")
        self.assertEqual(report["results"][0]["log"], "")

    def test_script_error_fails_even_when_exit_zero(self):
        self.scene("broken.tscn")
        code, report, _ = self.cli()
        self.assertEqual(code, 1)
        self.assertEqual(report["results"][0]["status"], "fail")
        self.assertIn("SCRIPT ERROR", report["results"][0]["log"])

    def test_truncated_output_cannot_hide_error(self):
        self.scene("early_error.tscn")
        code, report, _ = self.cli()
        self.assertEqual(code, 1)
        self.assertEqual(report["results"][0]["status"], "fail")

    def test_nonzero_exit_detected(self):
        self.scene("exit_fail.tscn")
        code, report, _ = self.cli()
        self.assertEqual(code, 1)
        self.assertEqual(report["results"][0]["exit_code"], 3)

    def test_timeout_detected_and_suite_continues(self):
        self.scene("timeout.tscn")
        self.scene("z.tscn")
        code, report, _ = self.cli("--timeout", "1")
        self.assertEqual(code, 1)
        self.assertEqual([r["status"] for r in report["results"]], ["timeout", "pass"])

    def test_import_success(self):
        self.scene("a.tscn")
        code, report, _ = self.cli("--import-first")
        self.assertEqual(code, 0)
        self.assertNotIn("import", report)

    def test_import_failure_short_circuit(self):
        self.scene("a.tscn")
        with mock.patch.dict(os.environ, {"FAIL_IMPORT": "1"}):
            code, report, _ = self.cli("--import-first")
        self.assertEqual(code, 1)
        self.assertEqual(report["results"], [])
        self.assertEqual(report["import"]["status"], "fail")

    def test_missing_godot(self):
        self.scene("a.tscn")
        proc = subprocess.run([sys.executable, str(TOOL), str(self.root), "--godot", "/definitely/no/godot"], capture_output=True, text=True)
        self.assertEqual(proc.returncode, 2)
        self.assertIn("not found", proc.stderr)

    def test_missing_project(self):
        (self.root / "project.godot").unlink()
        code, _, stderr = self.cli()
        self.assertEqual(code, 2)
        self.assertIn("project.godot", stderr)

    def test_bad_cli_limits(self):
        for flag, value in (("--timeout", "0"), ("--frames", "0"), ("--max-scenes", "-1"), ("--frames", "10001")):
            with self.subTest(flag=flag, value=value):
                code, _, _ = self.cli(flag, value)
                self.assertEqual(code, 2)

    def test_scene_limit(self):
        self.scene("a.tscn")
        self.scene("b.tscn")
        code, _, stderr = self.cli("--max-scenes", "1")
        self.assertEqual(code, 2)
        self.assertIn("exceeds", stderr)

    def test_scene_symlink_rejected(self):
        external = Path(self.temp.name) / "external.tscn"
        external.write_text("outside", encoding="utf-8")
        try:
            (self.root / "bad.tscn").symlink_to(external)
        except OSError:
            self.skipTest("symlinks unavailable")
        code, _, stderr = self.cli()
        self.assertEqual(code, 2)
        self.assertIn("Unsafe scene", stderr)

    def test_directory_symlink_rejected(self):
        outside = Path(self.temp.name) / "external"
        outside.mkdir()
        try:
            (self.root / "outside").symlink_to(outside, target_is_directory=True)
        except OSError:
            self.skipTest("symlinks unavailable")
        code, _, stderr = self.cli()
        self.assertEqual(code, 2)
        self.assertIn("symlink", stderr)

    def test_case_collision(self):
        self.scene("A.tscn")
        self.scene("a.tscn")
        if not (self.root / "A.tscn").exists() or not (self.root / "a.tscn").exists():
            self.skipTest("case-insensitive filesystem")
        code, _, stderr = self.cli()
        self.assertEqual(code, 2)
        self.assertIn("collision", stderr)

    def test_no_shell_interpretation(self):
        self.scene("scene;echo IGNORE.tscn")
        code, report, _ = self.cli()
        self.assertEqual(code, 0)
        self.assertEqual(report["results"][0]["scene"], "scene;echo IGNORE.tscn")

    def test_godot_error_regex(self):
        self.assertTrue(smoke.ERROR_LINE.search("  ERROR: fail"))
        self.assertTrue(smoke.ERROR_LINE.search("SCRIPT ERROR: bad"))
        self.assertFalse(smoke.ERROR_LINE.search("some error in narration"))

    def test_non_scene_files_ignored(self):
        (self.root / "script.gd").write_text("broken", encoding="utf-8")
        self.assertEqual(smoke.discover_scenes(self.root), [])

    def test_text_output(self):
        self.scene("broken.tscn")
        proc = subprocess.run([sys.executable, str(TOOL), str(self.root), "--godot", str(self.stub)], capture_output=True, text=True)
        self.assertEqual(proc.returncode, 1)
        self.assertIn("FAIL broken.tscn", proc.stdout)
        self.assertIn("SCRIPT ERROR", proc.stderr)

    def test_partial_output_bounded(self):
        with mock.patch.object(smoke.subprocess, "run") as mocked:
            mocked.return_value.stdout = "a" * 20000
            mocked.return_value.stderr = ""
            mocked.return_value.returncode = 0
            code, output, timeout, has_errors = smoke.run_command(["ignored"], 1)
        self.assertEqual(code, 0)
        self.assertFalse(timeout)
        self.assertFalse(has_errors)
        self.assertEqual(len(output), smoke.LOG_LIMIT)

    def test_error_marker_detected_before_log_tail(self):
        with mock.patch.object(smoke.subprocess, "run") as mocked:
            mocked.return_value.stdout = "ERROR: early failure\n" + "x" * 10000
            mocked.return_value.stderr = ""
            mocked.return_value.returncode = 0
            code, log, timed_out, has_errors = smoke.run_command(["ignored"], 1)
        self.assertEqual(code, 0)
        self.assertFalse(timed_out)
        self.assertTrue(has_errors)
        self.assertEqual(len(log), smoke.LOG_LIMIT)

    def test_timeout_with_string_output(self):
        error = subprocess.TimeoutExpired(["godot"], 1, output="partial", stderr="ERROR: failed")
        with mock.patch.object(smoke.subprocess, "run", side_effect=error):
            code, log, timed_out, has_errors = smoke.run_command(["godot"], 1)
        self.assertIsNone(code)
        self.assertTrue(timed_out)
        self.assertTrue(has_errors)
        self.assertIn("partial", log)

    def test_timeout_with_bytes_output(self):
        error = subprocess.TimeoutExpired(["godot"], 1, output=b"abc", stderr=b"def")
        with mock.patch.object(smoke.subprocess, "run", side_effect=error):
            code, log, timed_out, has_errors = smoke.run_command(["godot"], 1)
        self.assertIsNone(code)
        self.assertTrue(timed_out)
        self.assertFalse(has_errors)
        self.assertIn("abc", log)

    def test_command_exec_failure(self):
        with mock.patch.object(smoke.subprocess, "run", side_effect=OSError("denied")):
            with self.assertRaisesRegex(smoke.SmokeError, "denied"):
                smoke.run_command(["godot"], 1)

    def test_junit_empty_suite(self):
        root = ET.fromstring(smoke.junit_report({"ok": True, "results": []}))
        self.assertEqual(root.tag, "testsuite")
        self.assertEqual(root.get("tests"), "0")
        self.assertEqual(root.get("failures"), "0")
        self.assertEqual(root.findall("testcase"), [])

    def test_junit_successful_scene(self):
        self.scene("a.tscn")
        completed = subprocess.run([sys.executable, str(TOOL), str(self.root),
                                    "--godot", str(self.stub), "--format", "junit"],
                                   capture_output=True, text=True)
        self.assertEqual(completed.returncode, 0)
        suite = ET.fromstring(completed.stdout)
        self.assertEqual(suite.get("tests"), "1")
        self.assertEqual(suite.get("failures"), "0")
        self.assertEqual(suite.find("testcase").get("name"), "a.tscn")
        self.assertIsNone(suite.find("testcase/failure"))

    def test_junit_script_error_failure(self):
        self.scene("broken.tscn")
        completed = subprocess.run([sys.executable, str(TOOL), str(self.root),
                                    "--godot", str(self.stub), "--format", "junit"],
                                   capture_output=True, text=True)
        self.assertEqual(completed.returncode, 1)
        suite = ET.fromstring(completed.stdout)
        self.assertEqual(suite.get("failures"), "1")
        self.assertIn("SCRIPT ERROR", suite.find("testcase/failure").text)

    def test_junit_import_failure(self):
        self.scene("a.tscn")
        with mock.patch.dict(os.environ, {"FAIL_IMPORT": "1"}):
            completed = subprocess.run([sys.executable, str(TOOL), str(self.root),
                                        "--godot", str(self.stub), "--format", "junit",
                                        "--import-first"], capture_output=True, text=True)
        self.assertEqual(completed.returncode, 1)
        suite = ET.fromstring(completed.stdout)
        self.assertEqual(suite.get("tests"), "1")
        self.assertEqual(suite.get("failures"), "1")
        self.assertEqual(suite.find("testcase").get("name"), "__import__")
        self.assertIsNotNone(suite.find("testcase/failure"))

    def test_junit_timeout_case(self):
        report = {"ok": False, "results": [
            {"scene": "slow.tscn", "status": "timeout", "exit_code": None, "log": "timeout"}]}
        suite = ET.fromstring(smoke.junit_report(report))
        self.assertEqual(suite.get("failures"), "1")
        self.assertEqual(suite.find("testcase/failure").get("type"), "timeout")

    def test_junit_escapes_xml_and_invalid_unicode(self):
        report = {"ok": False, "results": [
            {"scene": "a<&\\u0000.tscn", "status": "fail",
             "exit_code": 1, "log": "ERROR: bad <&\\u0000"}]}
        # Keep an actual NUL in the input; XML 1.0 forbids it.
        report["results"][0]["scene"] = report["results"][0]["scene"].replace("\\u0000", chr(0))
        report["results"][0]["log"] = report["results"][0]["log"].replace("\\u0000", chr(0))
        xml = smoke.junit_report(report)
        suite = ET.fromstring(xml)
        self.assertNotIn(chr(0), xml)
        self.assertIn("<&", suite.find("testcase").get("name"))
        self.assertIn("ERROR: bad <&", suite.find("testcase/failure").text)


    def test_exact_selection_restricts_scene_execution(self):
        self.scene("broken.tscn")
        self.scene("scenes/healthy.tscn")
        code, report, _ = self.cli("--scene", "res://scenes/healthy.tscn", "--require-scenes")
        self.assertEqual(code, 0)
        self.assertEqual([item["scene"] for item in report["results"]], ["scenes/healthy.tscn"])

    def test_relative_path_selection_is_supported(self):
        self.scene("broken.tscn")
        self.scene("healthy.tscn")
        code, report, _ = self.cli("--scene", "healthy.tscn")
        self.assertEqual(code, 0)
        self.assertEqual([item["scene"] for item in report["results"]], ["healthy.tscn"])

    def test_repeat_selection_does_not_duplicate_tests(self):
        self.scene("healthy.tscn")
        code, report, _ = self.cli("--scene", "healthy.tscn", "--scene", "res://healthy.tscn")
        self.assertEqual(code, 0)
        self.assertEqual(len(report["results"]), 1)

    def test_multiple_explicit_scenes_keep_sorted_order(self):
        self.scene("z.tscn")
        self.scene("a.tscn")
        code, report, _ = self.cli("--scene", "z.tscn", "--scene", "a.tscn")
        self.assertEqual(code, 0)
        self.assertEqual([x["scene"] for x in report["results"]], ["a.tscn", "z.tscn"])

    def test_selected_scene_missing_is_error(self):
        self.scene("healthy.tscn")
        code, report, stderr = self.cli("--scene", "res://missing.tscn")
        self.assertEqual(code, 2)
        self.assertIsNone(report)
        self.assertIn("not found", stderr)

    def test_selected_scene_excluded_is_error(self):
        self.scene("healthy.tscn")
        code, _, stderr = self.cli("--scene", "healthy.tscn", "--exclude", "*.tscn")
        self.assertEqual(code, 2)
        self.assertIn("not found", stderr)

    def test_malformed_explicit_scene_paths_are_rejected(self):
        self.scene("healthy.tscn")
        for name in ("", "res://", "/healthy.tscn", "res://../healthy.tscn",
                     "res://foo/../healthy.tscn", "./healthy.tscn", "res://./healthy.tscn",
                     "res://foo//bar.tscn", "C:/healthy.tscn", "res://foo\\bar.tscn"):
            with self.subTest(name=name):
                code, _, stderr = self.cli("--scene", name)
                self.assertEqual(code, 2)
                self.assertIn("Invalid scene selection", stderr)

    def test_scene_selection_is_case_sensitive(self):
        self.scene("MyScene.tscn")
        code, _, stderr = self.cli("--scene", "myscene.tscn")
        self.assertEqual(code, 2)
        self.assertIn("not found", stderr)

    def test_require_scenes_rejects_empty_project(self):
        code, report, stderr = self.cli("--require-scenes")
        self.assertEqual(code, 2)
        self.assertIsNone(report)
        self.assertIn("No scenes selected", stderr)

    def test_require_scenes_rejects_all_excluded(self):
        self.scene("healthy.tscn")
        code, _, stderr = self.cli("--exclude", "*.tscn", "--require-scenes")
        self.assertEqual(code, 2)
        self.assertIn("No scenes selected", stderr)



if __name__ == "__main__":
    unittest.main()
