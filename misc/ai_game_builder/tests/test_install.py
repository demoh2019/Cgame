from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from install import install, main


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.project = self.root / "my_game"
        self.project.mkdir()
        (self.project / "project.godot").write_text("config_version=5\n")

    def tearDown(self):
        self.tmp.cleanup()

    def test_install_all_plugin_files(self):
        folder = install(self.project)
        self.assertTrue((folder / "plugin.cfg").is_file())
        self.assertTrue((folder / "assistant_dock.gd").is_file())
        self.assertTrue((folder / "plan.gd").is_file())
        self.assertTrue((folder / "writer.gd").is_file())

    def test_does_not_modify_project_settings(self):
        before = (self.project / "project.godot").read_bytes()
        install(self.project)
        self.assertEqual((self.project / "project.godot").read_bytes(), before)

    def test_refuses_overwrite_by_default(self):
        folder = install(self.project)
        (folder / "custom.gd").write_text("user data")
        with self.assertRaises(FileExistsError):
            install(self.project)
        self.assertEqual((folder / "custom.gd").read_text(), "user data")

    def test_force_replaces_existing_files(self):
        folder = install(self.project)
        (folder / "custom.gd").write_text("obsolete")
        install(self.project, force=True)
        self.assertFalse((folder / "custom.gd").exists())
        self.assertTrue((folder / "plugin.cfg").is_file())

    def test_rejects_missing_project_file(self):
        with self.assertRaises(ValueError):
            install(self.root)

    def test_rejects_non_directory(self):
        with self.assertRaises(ValueError):
            install(self.root / "missing")

    def test_rejects_symlinked_addon_dir(self):
        addons = self.project / "addons"
        addons.mkdir()
        destination = addons / "ai_game_builder"
        destination.symlink_to(self.root, target_is_directory=True)
        with self.assertRaises((ValueError, FileExistsError)):
            install(self.project, force=True)
        self.assertTrue(destination.is_symlink())

    def test_rejects_leftover_staging_directory(self):
        (self.project / "addons").mkdir()
        (self.project / "addons" / "ai_game_builder.installing").mkdir()
        with self.assertRaises(FileExistsError):
            install(self.project)

    def test_cli_installs(self):
        self.assertEqual(main(["--project", str(self.project)]), 0)

    def test_cli_rejects_bad_path(self):
        with patch("sys.stderr"):
            self.assertEqual(main(["--project", str(self.root)]), 1)


if __name__ == "__main__":
    unittest.main()
