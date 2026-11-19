"""Tests for the browser export/publishing helper (stdlib unittest only)."""

import contextlib
import importlib.util
import io
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch


PUBLISH_PATH = Path(__file__).resolve().parents[1] / "publish.py"
spec = importlib.util.spec_from_file_location("godot_web_publish", PUBLISH_PATH)
publish = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publish)


class PublishTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.project = self.root / "My Project"
        self.project.mkdir()
        (self.project / "project.godot").write_text('config_version=5\n', encoding="utf-8")
        self.bundle = self.root / "Web Export"
        self.bundle.mkdir()
        self.write_bundle(self.bundle)

    @staticmethod
    def write_bundle(directory, stem="index", threaded=False):
        directory.mkdir(exist_ok=True, parents=True)
        (directory / f"{stem}.html").write_text(
            f'<script src="{stem}.js"></script>\n'
            f"<script>const GODOT_THREADS_ENABLED = {'true' if threaded else 'false'};</script>",
            encoding="utf-8",
        )
        (directory / f"{stem}.js").write_text("console.log('godot');", encoding="utf-8")
        (directory / f"{stem}.wasm").write_bytes(b"\x00asm\x01\x00\x00\x00")
        (directory / f"{stem}.pck").write_bytes(b"GDPC\x00\x00\x00\x00")

    def test_find_preset_with_matching_name_and_platform(self):
        text = '[preset.0]\nname="Linux"\nplatform="Linux/X11"\n[preset.1]\nname="Web"\nplatform="Web"\n'
        self.assertTrue(publish.find_web_preset(text, "Web"))
        self.assertFalse(publish.find_web_preset(text, "Linux"))

    def test_find_preset_does_not_mix_sections(self):
        text = '[preset.0]\nname="Web"\nplatform="Windows Desktop"\n[preset.1]\nname="Desktop"\nplatform="Web"\n'
        self.assertFalse(publish.find_web_preset(text, "Web"))

    def test_find_preset_ignores_options_section(self):
        text = '[preset.0]\nname="Web"\n[preset.0.options]\nplatform="Web"\n'
        self.assertFalse(publish.find_web_preset(text, "Web"))

    def test_find_preset_supports_custom_name(self):
        self.assertTrue(publish.find_web_preset(publish.make_web_preset("Browser release"), "Browser release"))

    def test_find_preset_ignores_bad_json(self):
        self.assertFalse(publish.find_web_preset('[preset.0]\nname="bad\\x"\nplatform="Web"\n', "bad"))

    def test_generated_preset_is_unthreaded(self):
        p = publish.make_web_preset()
        self.assertIn("variant/thread_support=false", p)
        self.assertIn("variant/extensions_support=false", p)
        self.assertIn("progressive_web_app/enabled=false", p)

    def test_generated_preset_can_enable_pwa(self):
        self.assertIn("progressive_web_app/enabled=true", publish.make_web_preset(pwa=True))

    def test_temp_preset_is_deleted_after_success(self):
        cfg = self.project / "export_presets.cfg"
        with publish.web_preset(self.project, "Web"):
            self.assertTrue(cfg.exists())
        self.assertFalse(cfg.exists())

    def test_temp_preset_is_deleted_after_failure(self):
        cfg = self.project / "export_presets.cfg"
        with self.assertRaises(RuntimeError):
            with publish.web_preset(self.project, "Web"):
                raise RuntimeError("fake export failure")
        self.assertFalse(cfg.exists())

    def test_changed_temp_preset_is_preserved(self):
        cfg = self.project / "export_presets.cfg"
        with contextlib.redirect_stderr(io.StringIO()):
            with publish.web_preset(self.project, "Web"):
                cfg.write_text("edited by user", encoding="utf-8")
        self.assertEqual(cfg.read_text(encoding="utf-8"), "edited by user")

    def test_existing_web_preset_remains_unchanged(self):
        cfg = self.project / "export_presets.cfg"
        original = publish.make_web_preset()
        cfg.write_text(original, encoding="utf-8")
        with publish.web_preset(self.project, "Web"):
            self.assertEqual(cfg.read_text(encoding="utf-8"), original)
        self.assertEqual(cfg.read_text(encoding="utf-8"), original)

    def test_existing_without_web_preset_fails_without_modification(self):
        cfg = self.project / "export_presets.cfg"
        cfg.write_text('[preset.0]\nname="Desktop"\nplatform="Windows Desktop"\n', encoding="utf-8")
        with self.assertRaisesRegex(publish.PublishError, "Web preset"):
            with publish.web_preset(self.project, "Web"):
                pass
        self.assertIn('name="Desktop"', cfg.read_text(encoding="utf-8"))

    def test_check_valid_bundle(self):
        result = publish.check_export(self.bundle)
        self.assertEqual(result["entry"], "index.html")
        self.assertEqual(result["warnings"], [])
        self.assertEqual(len(result["required_files"]), 4)

    def test_check_rejects_missing_directory(self):
        with self.assertRaises(publish.PublishError):
            publish.check_export(self.root / "not_here")

    def test_check_rejects_missing_wasm(self):
        (self.bundle / "index.wasm").unlink()
        with self.assertRaisesRegex(publish.PublishError, "index.wasm"):
            publish.check_export(self.bundle)

    def test_check_rejects_empty_js(self):
        (self.bundle / "index.js").write_bytes(b"")
        with self.assertRaisesRegex(publish.PublishError, "index.js"):
            publish.check_export(self.bundle)

    def test_check_rejects_invalid_wasm_magic(self):
        (self.bundle / "index.wasm").write_bytes(b"xxxx")
        with self.assertRaisesRegex(publish.PublishError, "WebAssembly"):
            publish.check_export(self.bundle)

    def test_check_rejects_invalid_pack_magic(self):
        (self.bundle / "index.pck").write_bytes(b"xxxx")
        with self.assertRaisesRegex(publish.PublishError, "Godot package"):
            publish.check_export(self.bundle)

    def test_check_rejects_unexpanded_shell(self):
        with (self.bundle / "index.html").open("a", encoding="utf-8") as file:
            file.write("$GODOT_CONFIG")
        with self.assertRaisesRegex(publish.PublishError, "unexpanded"):
            publish.check_export(self.bundle)

    def test_check_detects_thread_headers_requirement(self):
        self.write_bundle(self.bundle, threaded=True)
        info = publish.check_export(self.bundle)
        self.assertIn("Cross-Origin-Embedder-Policy", info["warnings"][0])

    def test_check_warns_when_custom_html_lacks_threads_flag(self):
        (self.bundle / "index.html").write_text("<html>ready</html>", encoding="utf-8")
        self.assertIn("thread support", publish.check_export(self.bundle)["warnings"][0])

    def test_check_custom_stem(self):
        self.write_bundle(self.bundle, stem="mygame")
        self.assertEqual(publish.check_export(self.bundle, "mygame.html")["entry"], "mygame.html")

    def test_check_rejects_entry_path_traversal(self):
        with self.assertRaisesRegex(publish.PublishError, "single"):
            publish.check_export(self.bundle, "../index.html")

    def test_zip_contains_all_assets_at_archive_root(self):
        (self.bundle / "textures").mkdir()
        (self.bundle / "textures" / "tiles.png").write_bytes(b"PNG")
        archive = self.root / "publish.zip"
        count = publish.package_export(self.bundle, archive)
        self.assertEqual(count, 5)
        with zipfile.ZipFile(archive) as bundle:
            self.assertEqual(sorted(bundle.namelist()), [
                "index.html", "index.js", "index.pck", "index.wasm", "textures/tiles.png"
            ])

    def test_zip_rejects_inside_output_folder(self):
        with self.assertRaisesRegex(publish.PublishError, "outside"):
            publish.package_export(self.bundle, self.bundle / "game.zip")

    def test_zip_rejects_overwriting_archive(self):
        archive = self.root / "game.zip"
        archive.touch()
        with self.assertRaisesRegex(publish.PublishError, "already exists"):
            publish.package_export(self.bundle, archive)

    def test_zip_rejects_symlinks(self):
        try:
            (self.bundle / "untrusted").symlink_to(self.project, target_is_directory=True)
        except (OSError, NotImplementedError):
            self.skipTest("Symlinks are unavailable")
        with self.assertRaisesRegex(publish.PublishError, "symbolic"):
            publish.package_export(self.bundle, self.root / "game.zip")

    def test_export_rejects_missing_project(self):
        with self.assertRaisesRegex(publish.PublishError, "project.godot"):
            publish.export_project(self.root, self.root / "site")

    def test_export_rejects_existing_output(self):
        with self.assertRaisesRegex(publish.PublishError, "already exists"):
            publish.export_project(self.project, self.bundle)

    def test_export_rejects_missing_editor_executable(self):
        with patch.object(publish.shutil, "which", return_value=None):
            with self.assertRaisesRegex(publish.PublishError, "executable not found"):
                publish.export_project(self.project, self.root / "new-site")

    def test_export_successfully_publishes_and_cleans_preset(self):
        out = self.root / "new-site"

        def fake_export(argv, **kwargs):
            self.assertIn("--headless", argv)
            self.assertIn("--export-release", argv)
            self.assertEqual(argv[argv.index("--export-release") + 1], "Web")
            self.write_bundle(Path(argv[-1]).parent)
            return type("Result", (), {"returncode": 0, "stdout": "", "stderr": ""})()

        with patch.object(publish.shutil, "which", return_value="/some/godot"):
            with patch.object(publish.subprocess, "run", side_effect=fake_export):
                self.assertEqual(publish.export_project(self.project, out)["warnings"], [])
        self.assertTrue((out / "index.wasm").is_file())
        self.assertFalse((self.project / "export_presets.cfg").exists())
        self.assertEqual(len(list(self.root.glob("godot-web-*"))), 0)

    def test_export_error_leaves_no_partial_output(self):
        out = self.root / "new-site"
        result = type("Result", (), {"returncode": 1, "stdout": "oops", "stderr": "missing templates"})()
        with patch.object(publish.shutil, "which", return_value="/some/godot"):
            with patch.object(publish.subprocess, "run", return_value=result):
                with self.assertRaisesRegex(publish.PublishError, "missing templates"):
                    publish.export_project(self.project, out)
        self.assertFalse(out.exists())
        self.assertFalse((self.project / "export_presets.cfg").exists())

    def test_export_fails_validation_without_publishing(self):
        out = self.root / "new-site"
        result = type("Result", (), {"returncode": 0, "stdout": "", "stderr": ""})()
        with patch.object(publish.shutil, "which", return_value="/some/godot"):
            with patch.object(publish.subprocess, "run", return_value=result):
                with self.assertRaisesRegex(publish.PublishError, "Missing or empty"):
                    publish.export_project(self.project, out)
        self.assertFalse(out.exists())

    def test_main_check_success(self):
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(publish.main(["check", str(self.bundle)]), 0)

    def test_main_check_failure(self):
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(publish.main(["check", str(self.root / "missing")]), 1)

    def test_main_zip_success(self):
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(publish.main(["zip", str(self.bundle), str(self.root / "game.zip")]), 0)
        self.assertTrue((self.root / "game.zip").exists())


if __name__ == "__main__":
    unittest.main()
