"""Integration/regression tests for safe, non-destructive staged content updates."""

import hashlib
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import unittest
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import content_manifest as manifest
import content_delta_bundle as delta
import content_staged_update as staging


class StagedContentTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.base = Path(temp.name)
        self.installed = self.base / "installed"
        self.installed.mkdir()
        self.next = self.base / "next-release"
        self.new_files = self.base / "new-content"
        self.new_files.mkdir()
        self.bundle = self.base / "delta.zip"
        self.old_manifest = self.base / "old.json"
        self.new_manifest = self.base / "new.json"

    def prepare(self, old, new):
        def write(root, data):
            for name, payload in data.items():
                path = root.joinpath(*name.split("/"))
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(payload)
        write(self.installed, old)
        write(self.new_files, new)
        self.old_manifest.write_text(json.dumps(manifest.inventory(self.installed)), encoding="utf8")
        self.new_manifest.write_text(json.dumps(manifest.inventory(self.new_files)), encoding="utf8")
        delta.pack(self.old_manifest, self.new_manifest, self.new_files, self.bundle)

    def stage(self):
        return staging.stage(self.old_manifest, self.new_manifest, self.installed, self.bundle, self.next)

    def test_full_update_add_change_reuse_delete(self):
        self.prepare({"keep": b"same", "changed": b"before", "deleted": b"gone"},
                     {"keep": b"same", "changed": b"after", "added": b"fresh"})
        result = self.stage()
        self.assertEqual(result["staged_files"], 3)
        self.assertEqual(result["delta_files"], 2)
        self.assertEqual(result["reused_files"], 1)
        self.assertEqual(result["removed_files"], 1)
        self.assertEqual((self.next / "keep").read_bytes(), b"same")
        self.assertEqual((self.next / "changed").read_bytes(), b"after")
        self.assertEqual((self.next / "added").read_bytes(), b"fresh")
        self.assertFalse((self.next / "deleted").exists())
        self.assertEqual((self.installed / "changed").read_bytes(), b"before")
        self.assertTrue((self.installed / "deleted").exists())
        self.assertEqual(manifest.inventory(self.next), manifest.load_manifest(self.new_manifest))

    def test_old_install_is_unchanged(self):
        self.prepare({"a": b"x", "b": b"y"}, {"a": b"z"})
        before = manifest.inventory(self.installed)
        self.stage()
        self.assertEqual(manifest.inventory(self.installed), before)

    def test_empty_to_empty(self):
        self.prepare({}, {})
        self.assertEqual(self.stage()["staged_files"], 0)
        self.assertEqual(manifest.inventory(self.next)["files"], [])

    def test_empty_to_nonempty(self):
        self.prepare({}, {"nested/file": b"text"})
        self.assertEqual(self.stage()["delta_files"], 1)
        self.assertEqual((self.next / "nested/file").read_bytes(), b"text")

    def test_deletion_only_update(self):
        self.prepare({"removed": b"gone", "kept": b"same"}, {"kept": b"same"})
        self.assertEqual(self.stage()["delta_files"], 0)
        self.assertEqual(self.next.joinpath("kept").read_bytes(), b"same")
        self.assertFalse(self.next.joinpath("removed").exists())

    def test_no_change_update(self):
        self.prepare({"same": b"content"}, {"same": b"content"})
        self.assertEqual(self.stage()["reused_files"], 1)

    def test_nested_unicode_names(self):
        self.prepare({"café/文件.txt": b"previous"}, {"café/文件.txt": "новый".encode("utf-8")})
        self.assertEqual(self.stage()["delta_files"], 1)
        self.assertEqual((self.next / "café/文件.txt").read_bytes(), "новый".encode("utf-8"))

    def test_binary_file_and_zero_length(self):
        self.prepare({}, {"binary": bytes(range(256)), "empty": b""})
        self.stage()
        self.assertEqual((self.next / "binary").read_bytes(), bytes(range(256)))
        self.assertEqual((self.next / "empty").read_bytes(), b"")

    def test_large_file_streaming(self):
        data = b"x" * (2 * 1024 * 1024 + 17)
        self.prepare({"same": data}, {"same": data, "added": data})
        self.stage()
        self.assertEqual((self.next / "added").stat().st_size, len(data))
        self.assertEqual((self.next / "same").stat().st_size, len(data))

    def test_existing_output_refused_without_mutation(self):
        self.prepare({}, {"a": b"new"})
        self.next.mkdir()
        sentinel = self.next / "sentinel"
        sentinel.write_text("keep")
        with self.assertRaises(manifest.ManifestError):
            self.stage()
        self.assertEqual(sentinel.read_text(), "keep")

    def test_existing_broken_symlink_output_rejected(self):
        self.prepare({}, {})
        try:
            self.next.symlink_to(self.base / "missing", target_is_directory=True)
        except OSError:
            self.skipTest("Symlinks unsupported")
        with self.assertRaises(manifest.ManifestError):
            self.stage()

    def test_output_nested_in_installed_refused(self):
        self.prepare({"a": b"old"}, {"a": b"new"})
        with self.assertRaises(manifest.ManifestError):
            staging.stage(self.old_manifest, self.new_manifest, self.installed,
                          self.bundle, self.installed / "nested")

    def test_output_parent_does_not_exist(self):
        self.prepare({}, {})
        with self.assertRaises(manifest.ManifestError):
            staging.stage(self.old_manifest, self.new_manifest, self.installed,
                          self.bundle, self.base / "missing" / "new")

    def test_output_parent_symlink_refused(self):
        self.prepare({}, {})
        alias = self.base / "alias"
        try:
            alias.symlink_to(self.base, target_is_directory=True)
        except OSError:
            self.skipTest("Symlinks unsupported")
        with self.assertRaises(manifest.ManifestError):
            staging.stage(self.old_manifest, self.new_manifest, self.installed,
                          self.bundle, alias / "staged")

    def test_invalid_installed_root(self):
        self.prepare({}, {})
        with self.assertRaises(manifest.ManifestError):
            staging.stage(self.old_manifest, self.new_manifest, self.base / "missing",
                          self.bundle, self.next)

    def test_installed_root_symlink_rejected(self):
        self.prepare({"a": b"x"}, {"a": b"y"})
        alias = self.base / "alias"
        try:
            alias.symlink_to(self.installed, target_is_directory=True)
        except OSError:
            self.skipTest("Symlinks unsupported")
        with self.assertRaises(manifest.ManifestError):
            staging.stage(self.old_manifest, self.new_manifest, alias, self.bundle, self.next)

    def test_missing_old_content_refused(self):
        self.prepare({"old": b"old"}, {"old": b"new"})
        (self.installed / "old").unlink()
        with self.assertRaises(manifest.ManifestError):
            self.stage()
        self.assertFalse(self.next.exists())

    def test_modified_old_content_refused(self):
        self.prepare({"keep": b"yes"}, {"keep": b"yes"})
        (self.installed / "keep").write_bytes(b"bad")
        with self.assertRaises(manifest.ManifestError):
            self.stage()
        self.assertFalse(self.next.exists())

    def test_extra_old_content_refused(self):
        self.prepare({}, {})
        (self.installed / "extra").write_bytes(b"bad")
        with self.assertRaises(manifest.ManifestError):
            self.stage()

    def test_symlink_in_unchanged_old_content_refused(self):
        self.prepare({"a": b"same"}, {"a": b"same"})
        (self.installed / "a").unlink()
        try:
            (self.installed / "a").symlink_to(self.new_files / "a")
        except OSError:
            self.skipTest("Symlinks unsupported")
        with self.assertRaises(manifest.ManifestError):
            self.stage()

    def test_symlink_dir_in_old_content_refused(self):
        self.prepare({"nested/a": b"same"}, {"nested/a": b"same"})
        (self.installed / "nested/a").unlink()
        (self.installed / "nested").rmdir()
        (self.base / "external").mkdir()
        try:
            (self.installed / "nested").symlink_to(self.base / "external", target_is_directory=True)
        except OSError:
            self.skipTest("Symlinks unsupported")
        with self.assertRaises(manifest.ManifestError):
            self.stage()

    def test_zip_symlink_rejected(self):
        self.prepare({}, {"a": b"x"})
        alias = self.base / "alias.zip"
        try:
            alias.symlink_to(self.bundle)
        except OSError:
            self.skipTest("Symlinks unsupported")
        with self.assertRaises(manifest.ManifestError):
            staging.stage(self.old_manifest, self.new_manifest, self.installed, alias, self.next)

    def test_zip_tampered_hash_rejected_and_no_partial_stage(self):
        self.prepare({}, {"file": b"good"})
        with zipfile.ZipFile(self.bundle, "w", compression=zipfile.ZIP_STORED) as archive:
            archive.writestr("file", b"evil")
        with self.assertRaises(manifest.ManifestError):
            self.stage()
        self.assertFalse(self.next.exists())
        self.assertEqual(list(self.base.glob(".content-stage-*")), [])

    def test_zip_missing_entry_rejected(self):
        self.prepare({}, {"x": b"1"})
        with zipfile.ZipFile(self.bundle, "w"):
            pass
        with self.assertRaises(manifest.ManifestError):
            self.stage()

    def test_invalid_zip_rejected(self):
        self.prepare({}, {"x": b"1"})
        self.bundle.write_bytes(b"bad")
        with self.assertRaises(zipfile.BadZipFile):
            self.stage()

    def test_archive_member_symlink_rejected(self):
        self.prepare({}, {"file": b"data"})
        with zipfile.ZipFile(self.bundle, "w") as archive:
            entry = zipfile.ZipInfo("file")
            entry.create_system = 3
            entry.external_attr = (stat.S_IFLNK | 0o777) << 16
            archive.writestr(entry, b"data")
        with self.assertRaises(manifest.ManifestError):
            self.stage()

    def test_manifest_version_rejected(self):
        self.prepare({}, {"a": b"x"})
        doc = json.loads(self.new_manifest.read_text())
        doc["format"] = 99
        self.new_manifest.write_text(json.dumps(doc))
        with self.assertRaises(manifest.ManifestError):
            self.stage()

    def test_traversal_manifest_rejected(self):
        self.prepare({}, {})
        doc = {"format": 1, "files": [{"path": "../escape", "bytes": 0, "sha256": hashlib.sha256(b"").hexdigest()}]}
        self.new_manifest.write_text(json.dumps(doc))
        with self.assertRaises(manifest.ManifestError):
            self.stage()
        self.assertFalse((self.base / "escape").exists())

    def test_manifest_stored_inside_installed_is_excluded(self):
        self.prepare({"file": b"same"}, {"file": b"same"})
        new_old_manifest = self.installed / "release.json"
        new_old_manifest.write_bytes(self.old_manifest.read_bytes())
        self.old_manifest = new_old_manifest
        self.assertEqual(self.stage()["reused_files"], 1)

    def test_stage_output_is_not_a_symlink(self):
        self.prepare({}, {"new": b"x"})
        self.stage()
        self.assertFalse(self.next.is_symlink())
        self.assertFalse((self.next / "new").is_symlink())

    def test_destination_file_permissions_are_nonexecutable(self):
        self.prepare({}, {"some/script": b"file"})
        self.stage()
        if os.name == "posix":
            self.assertEqual((self.next / "some/script").stat().st_mode & 0o111, 0)

    def test_stage_creates_no_install_scripts(self):
        self.prepare({}, {"file": b"data"})
        self.stage()
        self.assertEqual(sorted(p.name for p in self.next.iterdir()), ["file"])

    def test_failure_during_copy_cleans_staging_directory(self):
        from unittest.mock import patch
        self.prepare({"a": b"reused"}, {"a": b"reused", "b": b"fresh"})
        original = staging._copy_and_check
        calls = [0]
        def fail_after_one(*args, **kwargs):
            calls[0] += 1
            if calls[0] == 2:
                raise OSError("Simulated out-of-space")
            return original(*args, **kwargs)
        with patch.object(staging, "_copy_and_check", side_effect=fail_after_one):
            with self.assertRaises(OSError):
                self.stage()
        self.assertFalse(self.next.exists())
        self.assertEqual(list(self.base.glob(".content-stage-*")), [])
        self.assertEqual((self.installed / "a").read_bytes(), b"reused")

    def test_old_file_changed_after_preflight_is_rejected(self):
        from unittest.mock import patch
        self.prepare({"keep": b"initial"}, {"keep": b"initial"})
        original = staging._checked_old_file
        def replace_after_open(root, relative):
            fd, before = original(root, relative)
            (root / relative).write_bytes(b"different")
            return fd, before
        with patch.object(staging, "_checked_old_file", side_effect=replace_after_open):
            with self.assertRaises(manifest.ManifestError):
                self.stage()
        self.assertFalse(self.next.exists())
        self.assertEqual(list(self.base.glob(".content-stage-*")), [])

    def test_delta_modified_after_preflight_is_rejected(self):
        from unittest.mock import patch
        self.prepare({}, {"changed": b"good"})
        actual_verify = staging.verify_bundle
        def replace_after_check(*args):
            checked = actual_verify(*args)
            with zipfile.ZipFile(self.bundle, "w", compression=zipfile.ZIP_STORED) as archive:
                archive.writestr("changed", b"evil")
            return checked
        with patch.object(staging, "verify_bundle", side_effect=replace_after_check):
            with self.assertRaises(manifest.ManifestError):
                self.stage()
        self.assertFalse(self.next.exists())
        self.assertEqual(list(self.base.glob(".content-stage-*")), [])

    def test_cli_zip_replaced_after_preflight_has_clean_failure(self):
        from unittest.mock import patch
        self.prepare({}, {"file": b"good"})
        original_verify = staging.verify_bundle
        def change_zip(*args):
            result = original_verify(*args)
            with zipfile.ZipFile(self.bundle, "w"):
                pass
            return result
        with patch.object(staging, "verify_bundle", side_effect=change_zip):
            self.assertEqual(staging.main([str(self.old_manifest), str(self.new_manifest),
                                           str(self.installed), str(self.bundle),
                                           str(self.next)]), 2)
        self.assertFalse(self.next.exists())
        self.assertEqual(list(self.base.glob(".content-stage-*")), [])

    def test_cli_end_to_end(self):
        self.prepare({"a": b"one"}, {"a": b"two", "b": b"new"})
        cli = subprocess.run([sys.executable, str(Path(staging.__file__)),
                              str(self.old_manifest), str(self.new_manifest),
                              str(self.installed), str(self.bundle), str(self.next)],
                             capture_output=True, text=True)
        self.assertEqual(cli.returncode, 0, cli.stderr)
        self.assertEqual(json.loads(cli.stdout)["delta_files"], 2)
        self.assertEqual((self.next / "a").read_bytes(), b"two")

    def test_cli_rejected_existing_target_exit_code_two(self):
        self.prepare({}, {})
        self.next.mkdir()
        cli = subprocess.run([sys.executable, str(Path(staging.__file__)),
                              str(self.old_manifest), str(self.new_manifest),
                              str(self.installed), str(self.bundle), str(self.next)],
                             capture_output=True, text=True)
        self.assertEqual(cli.returncode, 2)
        self.assertIn("content_staged_update:", cli.stderr)


if __name__ == "__main__":
    unittest.main()
