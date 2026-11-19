"""Regression and integration tests for portable Godot build profiles."""

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
import build_profiles as bp


class ProfilesTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.project = Path(self.temp.name)
        (self.project / "project.godot").write_text("config_version=5\n", encoding="utf-8")
        (self.project / "export_presets.cfg").write_text(
            '[preset.0]\nname="Windows Desktop"\n[preset.0.options]\nname="ignore"\n'
            '[preset.1]\nname="Web"\n', encoding="utf-8")
        self.data = {"version": 1, "profiles": {
            "win": {"preset": "Windows Desktop", "mode": "release", "output": "builds/win/game.exe"},
            "web": {"preset": "Web", "mode": "pack", "output": "builds/web/site.zip"},
        }}
        self.config = self.project / "build_profiles.json"
        self.save()

    def save(self):
        self.config.write_text(json.dumps(self.data), encoding="utf-8")

    def load(self):
        return bp.load_profiles(self.project, self.config)

    def cli(self, *args):
        stdout = io.StringIO()
        stderr = io.StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            status = bp.main(list(args) + ["--project", str(self.project)])
        return status, stdout.getvalue(), stderr.getvalue()

    def test_valid_profiles_and_order(self):
        profiles = self.load()
        self.assertEqual(list(profiles), ["web", "win"])
        self.assertEqual(profiles["win"].preset, "Windows Desktop")

    def test_list(self):
        code, out, _ = self.cli("list")
        self.assertEqual(code, 0)
        self.assertIn("win: release", out)
        self.assertIn("web: pack", out)

    def test_validate(self):
        self.assertEqual(self.cli("validate")[0], 0)

    def test_plan_is_json_array_and_does_not_create_outputs(self):
        code, out, _ = self.cli("plan", "win", "--godot", "custom godot")
        self.assertEqual(code, 0)
        parts = json.loads(out)
        self.assertEqual(parts[:4], ["custom godot", "--headless", "--path", str(self.project)])
        self.assertEqual(parts[-3:-1], ["--export-release", "Windows Desktop"])
        self.assertFalse((self.project / "builds").exists())

    def test_plan_all(self):
        code, out, _ = self.cli("plan")
        self.assertEqual(code, 0)
        self.assertEqual(len(out.splitlines()), 2)

    def test_build_calls_godot_without_shell_and_makes_parent(self):
        with patch.object(bp.subprocess, "run") as run:
            run.return_value.returncode = 0
            code, _, _ = self.cli("build", "win")
        self.assertEqual(code, 0)
        self.assertTrue((self.project / "builds/win").is_dir())
        args, kwargs = run.call_args
        self.assertEqual(args[0][-3:-1], ["--export-release", "Windows Desktop"])
        self.assertEqual(kwargs["cwd"], self.project)
        self.assertFalse(kwargs["check"])

    def test_build_propagates_failure(self):
        with patch.object(bp.subprocess, "run") as run:
            run.return_value.returncode = 47
            self.assertEqual(self.cli("build", "web")[0], 47)

    def test_failed_launch(self):
        with patch.object(bp.subprocess, "run", side_effect=FileNotFoundError("missing")):
            code, _, err = self.cli("build", "win")
        self.assertEqual(code, 2)
        self.assertIn("Cannot launch", err)

    def test_build_requires_profile(self):
        self.assertEqual(self.cli("build")[0], 2)

    def test_unknown_profile(self):
        self.assertEqual(self.cli("plan", "linux")[0], 2)

    def test_requires_project(self):
        (self.project / "project.godot").unlink()
        with self.assertRaises(SystemExit):
            self.cli("validate")

    def test_existing_output_requires_opt_in(self):
        folder = self.project / "builds/win"
        folder.mkdir(parents=True)
        (folder / "game.exe").write_bytes(b"old")
        with patch.object(bp.subprocess, "run") as run:
            self.assertEqual(self.cli("build", "win")[0], 2)
            run.assert_not_called()
            run.return_value.returncode = 0
            self.assertEqual(self.cli("build", "win", "--overwrite")[0], 0)
            run.assert_called_once()

    def test_empty_object(self):
        self.data["profiles"] = {}
        self.save()
        with self.assertRaisesRegex(bp.ProfileError, "non-empty"):
            self.load()

    def test_duplicate_json_keys(self):
        self.config.write_text('{"version":1,"version":1,"profiles":{}}')
        with self.assertRaisesRegex(bp.ProfileError, "Duplicate JSON key"):
            self.load()

    def test_invalid_json(self):
        self.config.write_text("{invalid", encoding="utf-8")
        with self.assertRaisesRegex(bp.ProfileError, "Cannot read"):
            self.load()

    def test_missing_json(self):
        self.config.unlink()
        with self.assertRaises(bp.ProfileError):
            self.load()

    def test_schema_version_bool_not_accepted(self):
        for version in [True, 2, "1", None]:
            with self.subTest(version=version):
                self.data["version"] = version
                self.save()
                with self.assertRaises(bp.ProfileError):
                    self.load()

    def test_rejects_unknown_properties(self):
        self.data["profiles"]["win"]["cmd"] = "echo injected"
        self.save()
        with self.assertRaises(bp.ProfileError):
            self.load()

    def test_rejects_unknown_preset(self):
        self.data["profiles"]["win"]["preset"] = "Unlisted"
        self.save()
        with self.assertRaisesRegex(bp.ProfileError, "unknown export preset"):
            self.load()

    def test_rejects_invalid_mode(self):
        self.data["profiles"]["win"]["mode"] = "shell"
        self.save()
        with self.assertRaises(bp.ProfileError):
            self.load()

    def test_rejects_duplicate_output(self):
        self.data["profiles"]["web"]["output"] = "builds/win/game.exe"
        self.data["profiles"]["web"]["mode"] = "release"
        self.save()
        with self.assertRaisesRegex(bp.ProfileError, "Multiple profiles"):
            self.load()

    def test_pack_requires_pck_or_zip(self):
        self.data["profiles"]["web"]["output"] = "builds/web/game.exe"
        self.save()
        with self.assertRaisesRegex(bp.ProfileError, "pack output"):
            self.load()

    def test_rejects_nonportable_and_escaping_paths(self):
        invalid = ["/tmp/game.exe", "builds/../game.exe", "builds/a/../../escape",
                   "builds/a//game.exe", "builds/a/./game.exe", "builds/a/", "builds/a/CON",
                   "builds/a/prn.txt", "builds/a/a:game", "builds/a/hi?", "builds/a/hi.",
                   "builds/a/back\\slash", "builds/a/hi ", "builds/a/\x00", "other/a/out"]
        for path in invalid:
            with self.subTest(path=path):
                self.data["profiles"]["win"]["output"] = path
                self.save()
                with self.assertRaises(bp.ProfileError):
                    self.load()

    def test_symlink_escape(self):
        elsewhere = self.project / "elsewhere"
        elsewhere.mkdir()
        try:
            (self.project / "builds").symlink_to(elsewhere, target_is_directory=True)
        except (OSError, NotImplementedError):
            self.skipTest("Creating symlinks is not permitted on this runner")
        with self.assertRaisesRegex(bp.ProfileError, "Symlink"):
            self.load()

    def test_target_symlink(self):
        target = self.project / "builds/win"
        target.mkdir(parents=True)
        try:
            (target / "game.exe").symlink_to(self.project / "project.godot")
        except (OSError, NotImplementedError):
            self.skipTest("Creating symlinks is not permitted on this runner")
        with self.assertRaisesRegex(bp.ProfileError, "Symlink"):
            self.load()

    def test_output_directory_rejected(self):
        (self.project / "builds/win/game.exe").mkdir(parents=True)
        with self.assertRaisesRegex(bp.ProfileError, "not a regular file"):
            self.load()

    def test_parent_as_file_fails_cleanly(self):
        (self.project / "builds").write_text("file", encoding="utf-8")
        code, _, err = self.cli("build", "win")
        self.assertEqual(code, 2)
        self.assertIn("Cannot create build directory", err)

    @unittest.skipIf(os.name == "nt", "POSIX executable fixture")
    def test_real_subprocess_fixture(self):
        fake = self.project / "fake_godot"
        fake.write_text("#!/usr/bin/env python3\nimport sys\nfrom pathlib import Path\n"
                        "Path(sys.argv[-1]).write_text('exported')\n", encoding="utf-8")
        fake.chmod(0o755)
        code, _, err = self.cli("build", "win", "--godot", str(fake))
        self.assertEqual(code, 0, err)
        self.assertEqual((self.project / "builds/win/game.exe").read_text(), "exported")

    def test_invalid_names(self):
        for name in ["", "/oops", ".hidden?", "a" * 65]:
            with self.subTest(name=name):
                value = self.data["profiles"].pop("win")
                self.data["profiles"][name] = value
                self.save()
                with self.assertRaises(bp.ProfileError):
                    self.load()
                self.data["profiles"].pop(name)
                self.data["profiles"]["win"] = value

    def test_missing_export_presets(self):
        (self.project / "export_presets.cfg").unlink()
        with self.assertRaisesRegex(bp.ProfileError, "Missing Godot"):
            self.load()

    def test_duplicate_export_preset(self):
        with (self.project / "export_presets.cfg").open("a") as file:
            file.write('[preset.2]\nname="Web"\n')
        with self.assertRaisesRegex(bp.ProfileError, "duplicate"):
            self.load()

    def test_invalid_export_preset_name(self):
        (self.project / "export_presets.cfg").write_text('[preset.0]\nname={oops}\n')
        with self.assertRaisesRegex(bp.ProfileError, "Invalid export preset"):
            self.load()

    def test_no_named_presets(self):
        (self.project / "export_presets.cfg").write_text('[preset.0.options]\nname="fake"\n')
        with self.assertRaisesRegex(bp.ProfileError, "No named"):
            self.load()

    def test_case_sensitive_godot_preset(self):
        self.data["profiles"]["win"]["preset"] = "windows desktop"
        self.save()
        with self.assertRaises(bp.ProfileError):
            self.load()


if __name__ == "__main__":
    unittest.main()
