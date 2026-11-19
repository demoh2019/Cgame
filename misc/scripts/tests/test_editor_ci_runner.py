"""Offline regression coverage for the headless Godot test matrix runner."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import editor_ci_runner as ci


class EditorCITests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.project = self.root / "game"
        self.project.mkdir()
        (self.project / "project.godot").write_text("config_version=5\n")
        (self.project / "test.gd").write_text("extends SceneTree\n")
        (self.project / "main.tscn").write_text("[gd_scene format=3]\n")
        self.manifest = self.root / "matrix.json"
        self.binary = self.root / "fake_godot.py"
        self.binary.write_text("#!/usr/bin/env python3\nimport sys\nprint('|'.join(sys.argv[1:]))\nsys.exit(0)\n")
        self.binary.chmod(0o755)

    def case(self, kind="import", **kwargs):
        data = {"name": "smoke", "project": "game", "kind": kind, "timeout_seconds": 2}
        if kind == "script":
            data["entry"] = "res://test.gd"
        if kind == "scene":
            data.update({"entry": "res://main.tscn", "frames": 3})
        data.update(kwargs)
        return data

    def write(self, *cases, **fields):
        payload = {"format": 1, "cases": list(cases)}
        payload.update(fields)
        self.manifest.write_text(json.dumps(payload), encoding="utf-8")

    def assert_invalid(self, *cases, **fields):
        self.write(*cases, **fields)
        with self.assertRaises(ci.MatrixError):
            ci.load_matrix(self.manifest)

    def test_import_command(self):
        self.write(self.case())
        result = ci.run_matrix(self.manifest, str(self.binary))
        self.assertEqual((result["passed"], result["failed"]), (1, 0))
        self.assertIn("--editor|--import", result["results"][0]["output_excerpt"])

    def test_scene_command_and_frame_budget(self):
        self.write(self.case("scene"))
        text = ci.run_matrix(self.manifest, str(self.binary))["results"][0]["output_excerpt"]
        self.assertIn("--quit-after|3|--scene|res://main.tscn", text)

    def test_script_command(self):
        self.write(self.case("script"))
        self.assertIn("--script|res://test.gd", ci.run_matrix(self.manifest, str(self.binary))["results"][0]["output_excerpt"])

    def test_multiple_cases_preserve_order(self):
        self.write(self.case(name="a"), self.case("scene", name="b"))
        self.assertEqual([x["name"] for x in ci.run_matrix(self.manifest, str(self.binary))["results"]], ["a", "b"])

    def test_failure_exit_code(self):
        self.binary.write_text("#!/usr/bin/env python3\nimport sys\nsys.exit(7)\n")
        self.write(self.case())
        self.assertEqual(ci.run_matrix(self.manifest, str(self.binary))["results"][0]["exit_code"], 7)

    def test_missing_executable_is_reported(self):
        self.write(self.case())
        self.assertEqual(ci.run_matrix(self.manifest, "/missing/godot")["results"][0]["status"], "launch_error")

    def test_timeout_is_reported(self):
        self.binary.write_text("#!/usr/bin/env python3\nimport time\ntime.sleep(10)\n")
        self.write(self.case(timeout_seconds=1))
        self.assertEqual(ci.run_matrix(self.manifest, str(self.binary))["results"][0]["status"], "timeout")

    def test_output_excerpt_is_limited(self):
        self.binary.write_text("#!/usr/bin/env python3\nprint('A'*20000)\n")
        self.write(self.case())
        self.assertEqual(len(ci.run_matrix(self.manifest, str(self.binary))["results"][0]["output_excerpt"]), 8192)

    def test_cli_creates_json_report(self):
        self.write(self.case())
        report = self.root / "reports" / "out.json"
        cp = subprocess.run([sys.executable, str(Path(ci.__file__)), str(self.manifest), "--godot", str(self.binary), "--report", str(report)], capture_output=True, text=True)
        self.assertEqual(cp.returncode, 0, cp.stderr)
        self.assertEqual(json.loads(report.read_text())["passed"], 1)

    def test_cli_returns_failure(self):
        self.write(self.case())
        cp = subprocess.run([sys.executable, str(Path(ci.__file__)), str(self.manifest), "--godot", "/missing/godot"], capture_output=True, text=True)
        self.assertEqual(cp.returncode, 1)

    def test_cli_rejects_bad_manifest(self):
        self.manifest.write_text("{}")
        cp = subprocess.run([sys.executable, str(Path(ci.__file__)), str(self.manifest)], capture_output=True, text=True)
        self.assertEqual(cp.returncode, 2)

    def test_invalid_json(self):
        self.manifest.write_text("{")
        with self.assertRaises(ci.MatrixError):
            ci.load_matrix(self.manifest)

    def test_duplicate_json_keys(self):
        self.manifest.write_text('{"format":1,"format":1,"cases":[]}')
        with self.assertRaises(ci.MatrixError):
            ci.load_matrix(self.manifest)

    def test_no_cases(self):
        self.assert_invalid()

    def test_too_many_cases(self):
        self.assert_invalid(*[self.case(name=f"n{i}") for i in range(257)])

    def test_bad_format_type(self):
        self.assert_invalid(self.case(), format=True)

    def test_duplicate_name(self):
        self.assert_invalid(self.case(), self.case())

    def test_invalid_names(self):
        for name in ["", "a b", "a/b", "a" * 65, 12]:
            with self.subTest(name=name):
                self.assert_invalid(self.case(name=name))

    def test_bad_kinds(self):
        for kind in ["exec", "", None, 42]:
            with self.subTest(kind=kind):
                self.assert_invalid(self.case(kind=kind))

    def test_unexpected_fields(self):
        self.assert_invalid(self.case(inject="argument"))

    def test_timeout_validation(self):
        for timeout in [0, 301, True, 1.25, "1"]:
            with self.subTest(timeout=timeout):
                self.assert_invalid(self.case(timeout_seconds=timeout))

    def test_project_path_traversal(self):
        for path in ["../outside", "/tmp", "C:/tmp", "game/..", "game\\dir", "game//bad", "game/."]:
            with self.subTest(path=path):
                self.assert_invalid(self.case(project=path))

    def test_project_not_found(self):
        self.assert_invalid(self.case(project="missing"))

    @unittest.skipUnless(hasattr(os, "symlink"), "requires symlink")
    def test_symlink_project_rejected(self):
        (self.root / "alias").symlink_to(self.project, target_is_directory=True)
        self.assert_invalid(self.case(project="alias"))

    def test_entry_traversal(self):
        for entry in ["res://../secret.gd", "res:///absolute.gd", "res://x\\thing.gd", "res://missing.gd", "res://test.tscn"]:
            with self.subTest(entry=entry):
                self.assert_invalid(self.case("script", entry=entry))

    def test_scene_invalid_frames(self):
        for frames in [0, 1001, True, 1.2, "2"]:
            with self.subTest(frames=frames):
                self.assert_invalid(self.case("scene", frames=frames))

    def test_script_missing_entry(self):
        case = self.case("script")
        del case["entry"]
        self.assert_invalid(case)

    def test_manifest_size_limit(self):
        self.manifest.write_bytes(b" " * (ci.MAX_MANIFEST_BYTES + 1))
        with self.assertRaises(ci.MatrixError):
            ci.load_matrix(self.manifest)

    def test_report_is_atomically_replaced(self):
        dest = self.root / "report.json"
        dest.write_text("old")
        ci._write_report(dest, {"a": 1})
        self.assertEqual(json.loads(dest.read_text()), {"a": 1})

    def test_paths_resolve_with_nested_projects(self):
        child = self.root / "nested"
        child.mkdir()
        self.project.rename(child / "game")
        self.write(self.case(project="nested/game"))
        self.assertEqual(len(ci.load_matrix(self.manifest)), 1)


if __name__ == "__main__":
    unittest.main()
