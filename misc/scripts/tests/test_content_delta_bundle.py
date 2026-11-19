"""Regression tests for deterministic changed-file content packages."""

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
import content_delta_bundle as bundle
from content_manifest import ManifestError


class BundleTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        self.content = self.root / "new"
        self.content.mkdir()
        self.old = self.root / "old.json"
        self.new = self.root / "new.json"
        self.zip = self.root / "delta.zip"

    def manifest(self, path, files):
        entries = [{"path": name, "bytes": len(data),
                    "sha256": hashlib.sha256(data).hexdigest()}
                   for name, data in sorted(files.items())]
        path.write_text(json.dumps({"format": 1, "files": entries}), encoding="utf-8")

    def setup_versions(self, before, after):
        self.manifest(self.old, before)
        self.manifest(self.new, after)
        for name, content in after.items():
            target = self.content / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(content)

    def pack(self):
        return bundle.pack(self.old, self.new, self.content, self.zip)

    def verify(self):
        return bundle.verify(self.old, self.new, self.zip)

    def test_adds_only_new_files(self):
        self.setup_versions({"same": b"x"}, {"same": b"x", "added": b"y"})
        self.assertEqual(self.pack()["files"], 1)
        with zipfile.ZipFile(self.zip) as z:
            self.assertEqual(z.namelist(), ["added"])
            self.assertEqual(z.read("added"), b"y")
        self.assertTrue(self.verify()["ok"])

    def test_changed_file_is_bundled(self):
        self.setup_versions({"x": b"old"}, {"x": b"new"})
        self.pack()
        with zipfile.ZipFile(self.zip) as z:
            self.assertEqual(z.read("x"), b"new")
        self.assertEqual(self.verify()["bytes"], 3)

    def test_same_size_new_content(self):
        self.setup_versions({"x": b"one"}, {"x": b"two"})
        self.assertEqual(self.pack()["files"], 1)

    def test_removals_are_not_zip_entries(self):
        self.setup_versions({"removed": b"gone"}, {})
        self.assertEqual(self.pack()["removed"], ["removed"])
        with zipfile.ZipFile(self.zip) as z:
            self.assertEqual(z.namelist(), [])
        self.assertEqual(self.verify()["removed"], ["removed"])

    def test_no_changes_gives_empty_zip(self):
        self.setup_versions({"same": b"yes"}, {"same": b"yes"})
        self.assertEqual(self.pack()["files"], 0)
        self.assertEqual(self.verify()["files"], 0)

    def test_renames_are_add_and_remove(self):
        self.setup_versions({"old.txt": b"same"}, {"new.txt": b"same"})
        self.assertEqual(self.pack()["removed"], ["old.txt"])
        with zipfile.ZipFile(self.zip) as z:
            self.assertEqual(z.namelist(), ["new.txt"])

    def test_nested_paths_and_sorted_entries(self):
        self.setup_versions({}, {"z/last.txt": b"3", "a/first.txt": b"1", "b.txt": b"2"})
        self.pack()
        with zipfile.ZipFile(self.zip) as z:
            self.assertEqual(z.namelist(), ["a/first.txt", "b.txt", "z/last.txt"])
        self.verify()

    def test_unicode_nfc_paths(self):
        self.setup_versions({}, {"café/文件.txt": "привет".encode()})
        self.pack()
        self.verify()

    def test_zero_byte_file(self):
        self.setup_versions({}, {"zero": b""})
        self.pack()
        self.assertEqual(self.verify()["bytes"], 0)

    def test_deterministic_zip_bytes(self):
        self.setup_versions({}, {"x": b"abc", "sub/y": b"def"})
        self.pack()
        first = self.zip.read_bytes()
        self.pack()
        self.assertEqual(first, self.zip.read_bytes())

    def test_fixed_metadata_and_uncompressed_entries(self):
        self.setup_versions({}, {"file": b"a" * 100})
        self.pack()
        with zipfile.ZipFile(self.zip) as z:
            entry = z.infolist()[0]
            self.assertEqual(entry.date_time, bundle.FIXED_DATE)
            self.assertEqual(entry.compress_type, zipfile.ZIP_STORED)
            self.assertEqual((entry.external_attr >> 16) & 0o170000, stat.S_IFREG)

    def test_wrong_source_hash_preserves_existing_bundle(self):
        self.setup_versions({}, {"file": b"correct"})
        self.zip.write_bytes(b"previous-good-bundle")
        (self.content / "file").write_bytes(b"tampered")
        with self.assertRaises(ManifestError):
            self.pack()
        self.assertEqual(self.zip.read_bytes(), b"previous-good-bundle")

    def test_missing_source_rejected(self):
        self.setup_versions({}, {"lost": b"abc"})
        (self.content / "lost").unlink()
        with self.assertRaises(OSError):
            self.pack()
        self.assertFalse(self.zip.exists())

    def test_rejects_symlink_source(self):
        self.setup_versions({}, {"file": b"abc"})
        (self.content / "file").unlink()
        try:
            (self.content / "file").symlink_to(self.old)
        except OSError:
            self.skipTest("symlink unsupported")
        with self.assertRaises(ManifestError):
            self.pack()

    def test_rejects_symlink_directory(self):
        self.setup_versions({}, {"nested/file": b"abc"})
        (self.content / "nested/file").unlink()
        (self.content / "nested").rmdir()
        elsewhere = self.root / "elsewhere"
        elsewhere.mkdir()
        try:
            (self.content / "nested").symlink_to(elsewhere, target_is_directory=True)
        except OSError:
            self.skipTest("symlink unsupported")
        with self.assertRaises(ManifestError):
            self.pack()

    def test_rejects_symlink_bundle_output(self):
        self.setup_versions({}, {"x": b"abc"})
        target = self.root / "dont-touch"
        target.write_bytes(b"safe")
        try:
            self.zip.symlink_to(target)
        except OSError:
            self.skipTest("symlink unsupported")
        with self.assertRaises(ManifestError):
            self.pack()
        self.assertEqual(target.read_bytes(), b"safe")

    def test_rejects_symlink_bundle_input(self):
        self.setup_versions({}, {"x": b"abc"})
        self.pack()
        alias = self.root / "alias.zip"
        try:
            alias.symlink_to(self.zip)
        except OSError:
            self.skipTest("symlink unsupported")
        with self.assertRaises(ManifestError):
            bundle.verify(self.old, self.new, alias)

    def test_rejects_zip_overwriting_source(self):
        self.setup_versions({}, {"delta.zip": b"source"})
        output = self.content / "delta.zip"
        with self.assertRaises(ManifestError):
            bundle.pack(self.old, self.new, self.content, output)
        self.assertEqual(output.read_bytes(), b"source")

    def test_rejects_output_in_new_subdirectory(self):
        self.setup_versions({}, {"file": b"abc"})
        with self.assertRaises(ManifestError):
            bundle.pack(self.old, self.new, self.content, self.content / "artifacts" / "delta.zip")

    def test_rejects_invalid_root_even_for_empty_bundle(self):
        self.setup_versions({}, {})
        with self.assertRaises(ManifestError):
            bundle.pack(self.old, self.new, self.root / "missing", self.zip)

    def test_corrupted_archive_rejected(self):
        self.setup_versions({}, {"file": b"abc"})
        self.pack()
        self.zip.write_bytes(b"not-a-zip")
        with self.assertRaises(zipfile.BadZipFile):
            self.verify()

    def test_tampered_archive_contents_rejected(self):
        self.setup_versions({}, {"file": b"abc"})
        self.pack()
        with zipfile.ZipFile(self.zip, "w") as z:
            z.writestr("file", b"tampered")
        with self.assertRaises(ManifestError):
            self.verify()

    def test_extra_entry_rejected(self):
        self.setup_versions({}, {"file": b"abc"})
        self.pack()
        with zipfile.ZipFile(self.zip, "a") as z:
            z.writestr("extra", b"hi")
        with self.assertRaises(ManifestError):
            self.verify()

    def test_missing_entry_rejected(self):
        self.setup_versions({}, {"file": b"abc"})
        with zipfile.ZipFile(self.zip, "w"):
            pass
        with self.assertRaises(ManifestError):
            self.verify()

    def test_reordered_archive_entries_rejected(self):
        self.setup_versions({}, {"a": b"1", "b": b"2"})
        with zipfile.ZipFile(self.zip, "w") as z:
            z.writestr("b", b"2")
            z.writestr("a", b"1")
        with self.assertRaises(ManifestError):
            self.verify()

    def test_duplicate_entry_rejected(self):
        self.setup_versions({}, {"file": b"abc"})
        with zipfile.ZipFile(self.zip, "w") as z:
            z.writestr("file", b"abc")
            z.writestr("file", b"abc")
        with self.assertRaises(ManifestError):
            self.verify()

    def test_compressed_archive_rejected(self):
        self.setup_versions({}, {"file": b"abc"})
        with zipfile.ZipFile(self.zip, "w", zipfile.ZIP_DEFLATED) as z:
            z.writestr("file", b"abc")
        with self.assertRaises(ManifestError):
            self.verify()

    def test_directory_zip_entry_rejected(self):
        self.setup_versions({}, {"file": b"abc"})
        with zipfile.ZipFile(self.zip, "w") as z:
            z.writestr("file/", b"")
        with self.assertRaises(ManifestError):
            self.verify()

    def test_zip_symlink_mode_rejected(self):
        self.setup_versions({}, {"file": b"abc"})
        with zipfile.ZipFile(self.zip, "w") as z:
            info = zipfile.ZipInfo("file", bundle.FIXED_DATE)
            info.create_system = 3
            info.external_attr = (stat.S_IFLNK | 0o777) << 16
            z.writestr(info, b"abc")
        with self.assertRaises(ManifestError):
            self.verify()

    def test_invalid_manifest_rejected(self):
        self.setup_versions({}, {"file": b"abc"})
        self.new.write_text('{"format":2,"files":[]}', encoding="utf8")
        with self.assertRaises(ManifestError):
            self.pack()

    def test_cli_pack_and_verify(self):
        self.setup_versions({}, {"file": b"abc"})
        program = str(Path(bundle.__file__))
        first = subprocess.run([sys.executable, program, "pack", str(self.old), str(self.new),
                                str(self.content), str(self.zip)], capture_output=True, text=True)
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual(json.loads(first.stdout)["files"], 1)
        second = subprocess.run([sys.executable, program, "verify", str(self.old), str(self.new),
                                 str(self.zip)], capture_output=True, text=True)
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertTrue(json.loads(second.stdout)["ok"])

    def test_cli_error_exit_two(self):
        self.setup_versions({}, {"missing": b"abc"})
        (self.content / "missing").unlink()
        result = subprocess.run([sys.executable, str(Path(bundle.__file__)), "pack",
                                 str(self.old), str(self.new), str(self.content), str(self.zip)],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn("content_delta_bundle:", result.stderr)


if __name__ == "__main__":
    unittest.main()
