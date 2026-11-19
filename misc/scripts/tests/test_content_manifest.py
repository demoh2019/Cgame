"""Regression tests for deterministic, portable Godot content manifests."""

import contextlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import content_manifest as cm


class ContentManifestTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.project = self.base / "game"
        self.project.mkdir()
        self.manifest = self.project / "release.json"

    def put(self, name, contents=b"test"):
        path = self.project / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(contents)
        return path

    def build(self):
        doc = cm.inventory(self.project, "release.json")
        cm._write_manifest(self.manifest, doc)
        return doc

    def error(self, doc):
        self.manifest.write_text(json.dumps(doc), encoding="utf-8")
        with self.assertRaises(cm.ManifestError):
            cm.load_manifest(self.manifest)

    def cli(self, *args):
        return subprocess.run([sys.executable, str(Path(cm.__file__)), *map(str, args)],
                              text=True, capture_output=True, check=False)

    def test_empty_manifest(self):
        self.assertEqual(self.build(), {"format": 1, "files": []})

    def test_nested_entries_are_sorted(self):
        self.put("z/file.txt")
        self.put("a/file.txt")
        self.assertEqual([v["path"] for v in self.build()["files"]], ["a/file.txt", "z/file.txt"])

    def test_sha256_known_value(self):
        self.put("a", b"abc")
        row = self.build()["files"][0]
        self.assertEqual(row["sha256"], "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        self.assertEqual(row["bytes"], 3)

    def test_binary_file(self):
        self.put("binary", bytes(range(256)))
        self.assertEqual(self.build()["files"][0]["bytes"], 256)

    def test_large_file_streamed(self):
        self.put("large", b"x" * (2 * 1024 * 1024 + 1))
        self.assertEqual(self.build()["files"][0]["bytes"], 2 * 1024 * 1024 + 1)

    def test_valid_verification(self):
        self.put("data/a.txt", b"hello")
        self.build()
        self.assertEqual(cm.verify(self.project, self.manifest),
                         {"ok": True, "missing": [], "extra": [], "modified": []})

    def test_missing_file(self):
        self.put("gone")
        self.build()
        (self.project / "gone").unlink()
        self.assertEqual(cm.verify(self.project, self.manifest)["missing"], ["gone"])

    def test_unexpected_file(self):
        self.build()
        self.put("new")
        self.assertEqual(cm.verify(self.project, self.manifest)["extra"], ["new"])

    def test_modified_same_size(self):
        self.put("a", b"123")
        self.build()
        self.put("a", b"456")
        self.assertEqual(cm.verify(self.project, self.manifest)["modified"], ["a"])

    def test_modified_different_size(self):
        self.put("a", b"123")
        self.build()
        self.put("a", b"1234")
        self.assertEqual(cm.verify(self.project, self.manifest)["modified"], ["a"])

    def test_multiple_discrepancies_are_sorted(self):
        self.put("z")
        self.put("a")
        self.build()
        (self.project / "z").unlink()
        (self.project / "a").unlink()
        self.put("y")
        self.put("b")
        report = cm.verify(self.project, self.manifest)
        self.assertEqual(report["missing"], ["a", "z"])
        self.assertEqual(report["extra"], ["b", "y"])

    def test_rebuild_is_byte_identical(self):
        self.put("a", b"one")
        self.build()
        initial = self.manifest.read_bytes()
        self.build()
        self.assertEqual(self.manifest.read_bytes(), initial)

    def test_manifest_output_not_self_included(self):
        self.put("foo")
        self.build()
        self.assertEqual([v["path"] for v in self.build()["files"]], ["foo"])

    def test_external_manifest_no_exclusions(self):
        self.put("foo")
        self.build()
        external = self.base / "release.json"
        external.write_bytes(self.manifest.read_bytes())
        self.assertEqual(cm.verify(self.project, external)["extra"], ["release.json"])

    def test_unicode_nfc_filename(self):
        self.put("café/文件.txt")
        self.assertEqual(self.build()["files"][0]["path"], "café/文件.txt")

    def test_hidden_project_files_allowed(self):
        self.put(".keep/a")
        self.assertEqual(self.build()["files"][0]["path"], ".keep/a")

    def test_skips_generated_directories(self):
        for name in cm.SKIP_DIRS:
            self.put(name + "/ignored.txt")
        self.assertEqual(self.build()["files"], [])

    def test_skips_os_metadata_files(self):
        for name in cm.SKIP_FILES:
            self.put(name)
        self.assertEqual(self.build()["files"], [])

    def test_rejects_file_symlink(self):
        target = self.put("original")
        try:
            (self.project / "alias").symlink_to(target)
        except OSError:
            self.skipTest("symlink creation not supported")
        with self.assertRaises(cm.ManifestError):
            self.build()

    def test_rejects_directory_symlink(self):
        target = self.base / "outside"
        target.mkdir()
        try:
            (self.project / "linked").symlink_to(target, target_is_directory=True)
        except OSError:
            self.skipTest("symlink creation not supported")
        with self.assertRaises(cm.ManifestError):
            self.build()

    def test_rejects_symlink_project_root(self):
        link = self.base / "alias"
        try:
            link.symlink_to(self.project, target_is_directory=True)
        except OSError:
            self.skipTest("symlink creation not supported")
        with self.assertRaises(cm.ManifestError):
            cm.inventory(link)

    def test_rejects_case_alias_files(self):
        self.put("Sprite.png")
        self.put("sprite.png")
        if len(list(self.project.iterdir())) < 2:
            self.skipTest("case-insensitive host")
        with self.assertRaises(cm.ManifestError):
            self.build()

    def test_rejects_case_alias_parent_directories(self):
        self.put("Textures/a.png")
        self.put("textures/b.png")
        if len(list(self.project.iterdir())) < 2:
            self.skipTest("case-insensitive host")
        with self.assertRaises(cm.ManifestError):
            self.build()

    def test_manifest_rejects_file_directory_collisions(self):
        row = {"bytes": 0, "sha256": "a" * 64}
        for paths in (["data", "data/sprite.png"],
                      ["assets/world", "assets/world/maps/file"],
                      ["one", "one/two"]):
            with self.subTest(paths=paths):
                self.error({"format": 1, "files": [
                    {"path": name, **row} for name in sorted(paths)]})

    def test_scan_does_not_ignore_unreadable_directories(self):
        self.put("safe.txt")

        def broken_walk(root, *, followlinks, onerror):
            self.assertFalse(followlinks)
            self.assertTrue(callable(onerror))
            yield str(root), [], ["safe.txt"]
            onerror(PermissionError("unreadable nested directory"))

        with patch.object(cm.os, "walk", side_effect=broken_walk):
            with self.assertRaisesRegex(cm.ManifestError, "Cannot traverse project tree"):
                cm.inventory(self.project)

    def test_rejects_decomposed_unicode(self):
        with self.assertRaises(cm.ManifestError):
            cm.validate_path("cafe\u0301.png")

    def test_rejects_unsafe_paths(self):
        cases = ["", "/abs", "../escape", "a/../x", "a//b", "./a", "a/./b",
                 "a\\b", "C:/file", "CON", "nul.txt", "folder/AUX.ext",
                 "COM1.txt", "LPT9", "name.", "name ", "a/ ", "a\x00x",
                 "a\n", "a\x7f", "a:thing"]
        for path in cases:
            with self.subTest(path=path), self.assertRaises(cm.ManifestError):
                cm.validate_path(path)

    def test_rejects_windows_forbidden_characters(self):
        for path in ["a<b", "a>b", 'quote".tscn', "broken|name", "glob?.txt",
                     "star*.gd", "sub/file?.png", "sub/a<b.tres"]:
            with self.subTest(path=path), self.assertRaises(cm.ManifestError):
                cm.validate_path(path)

    def test_rejects_surrogate_unicode_in_paths(self):
        for path in ["surrogate\\ud800.tscn", "sub/\\udfff.txt"]:
            with self.subTest(path=path), self.assertRaises(cm.ManifestError):
                cm.validate_path(path)

    def test_rejects_malicious_windows_names_in_loaded_manifest(self):
        for path in ["asset?.png", "scripts/a|b.gd", 'asset"name.tres', "a\\ud800.txt"]:
            with self.subTest(path=path):
                self.error({"format": 1, "files": [{"path": path, "bytes": 0, "sha256": "a" * 64}]})

    def test_rejects_nonportable_file_found_during_inventory(self):
        filename = "texture?.png"
        try:
            self.put(filename)
        except OSError:
            self.skipTest("Host file system disallows this filename")
        with self.assertRaises(cm.ManifestError):
            self.build()

    def test_accepts_normal_portable_paths(self):
        for path in ["a.txt", "sub/floor.tscn", "spaces allowed/file 1.tres", "ä/雪.png", ".hidden"]:
            with self.subTest(path=path):
                self.assertEqual(cm.validate_path(path), path)

    def test_nonexistent_root(self):
        with self.assertRaises(cm.ManifestError):
            cm.inventory(self.base / "absent")

    def test_rejects_too_many_files(self):
        self.put("a")
        self.put("b")
        with patch.object(cm, "MAX_FILES", 1), self.assertRaises(cm.ManifestError):
            self.build()

    def test_malformed_root_manifest(self):
        for doc in [None, [], {}, {"format": 2, "files": []},
                    {"format": True, "files": []},
                    {"format": 1, "files": [], "created": "now"},
                    {"format": 1, "files": {}}]:
            with self.subTest(doc=doc):
                self.error(doc)

    def test_malformed_entries(self):
        bad = [None, [], {}, {"path": "a", "bytes": 1},
               {"path": "a", "bytes": 1, "sha256": "a" * 64, "other": 0},
               {"path": 3, "bytes": 1, "sha256": "a" * 64}]
        for entry in bad:
            with self.subTest(entry=entry):
                self.error({"format": 1, "files": [entry]})

    def test_invalid_size_types(self):
        for size in [True, None, 3.5, "4", -1]:
            with self.subTest(size=size):
                self.error({"format": 1, "files": [{"path": "a", "bytes": size, "sha256": "a" * 64}]})

    def test_invalid_sha256(self):
        for sha in ["A" * 64, "a" * 63, "g" * 64, 7, None]:
            with self.subTest(sha=sha):
                self.error({"format": 1, "files": [{"path": "a", "bytes": 0, "sha256": sha}]})

    def test_unsorted_paths(self):
        doc = cm.inventory(self.project)
        entry = {"bytes": 0, "sha256": "a" * 64}
        doc["files"] = [{"path": "z", **entry}, {"path": "a", **entry}]
        self.error(doc)

    def test_duplicate_paths(self):
        entry = {"path": "a", "bytes": 0, "sha256": "a" * 64}
        self.error({"format": 1, "files": [entry, entry]})

    def test_manifest_case_alias(self):
        entry = {"bytes": 0, "sha256": "a" * 64}
        self.error({"format": 1, "files": [{"path": "A", **entry}, {"path": "a", **entry}]})

    def test_invalid_manifest_path(self):
        self.error({"format": 1, "files": [{"path": "../evil", "bytes": 0, "sha256": "a" * 64}]})

    def test_manifest_size_limit(self):
        self.manifest.write_bytes(b"x" * 10)
        with patch.object(cm, "MAX_MANIFEST_BYTES", 5), self.assertRaises(cm.ManifestError):
            cm.load_manifest(self.manifest)

    def test_manifest_entry_limit(self):
        self.manifest.write_text(json.dumps({"format": 1, "files": [{"path": "a", "bytes": 0, "sha256": "a"*64}]}))
        with patch.object(cm, "MAX_FILES", 0), self.assertRaises(cm.ManifestError):
            cm.load_manifest(self.manifest)

    def test_diff_added(self):
        old = {"files": []}
        new = {"files": [{"path": "a", "bytes": 4, "sha256": "a"}]}
        self.assertEqual(cm.diff(old, new), {"added": ["a"], "removed": [], "modified": [],
                                             "unchanged": 0, "download_bytes": 4})

    def test_diff_removed(self):
        row = {"path": "a", "bytes": 4, "sha256": "a"}
        self.assertEqual(cm.diff({"files": [row]}, {"files": []})["removed"], ["a"])

    def test_diff_changed(self):
        old = {"files": [{"path": "a", "bytes": 3, "sha256": "a"}]}
        new = {"files": [{"path": "a", "bytes": 3, "sha256": "b"}]}
        report = cm.diff(old, new)
        self.assertEqual(report["modified"], ["a"])
        self.assertEqual(report["download_bytes"], 3)

    def test_diff_unchanged(self):
        row = {"path": "a", "bytes": 1, "sha256": "a"}
        report = cm.diff({"files": [row]}, {"files": [row]})
        self.assertEqual(report["unchanged"], 1)
        self.assertEqual(report["download_bytes"], 0)

    def test_diff_mixed_total_bytes(self):
        a = {"path": "a", "bytes": 5, "sha256": "a"}
        b = {"path": "b", "bytes": 10, "sha256": "b"}
        c = {"path": "c", "bytes": 7, "sha256": "c"}
        report = cm.diff({"files": [a, b]}, {"files": [a, {**b, "sha256": "x"}, c]})
        self.assertEqual(report["download_bytes"], 17)
        self.assertEqual(report["unchanged"], 1)

    def test_cli_build_and_verify_success(self):
        self.put("main.tscn", b"scene")
        made = self.cli("build", self.project, "-o", self.manifest)
        self.assertEqual(made.returncode, 0, made.stderr)
        self.assertEqual(json.loads(made.stdout)["files"], 1)
        checked = self.cli("verify", self.project, self.manifest)
        self.assertEqual(checked.returncode, 0, checked.stderr)
        self.assertTrue(json.loads(checked.stdout)["ok"])

    def test_cli_verify_mismatch_exit_one(self):
        self.build()
        self.put("new")
        checked = self.cli("verify", self.project, self.manifest)
        self.assertEqual(checked.returncode, 1)
        self.assertEqual(json.loads(checked.stdout)["extra"], ["new"])

    def test_cli_bad_manifest_exit_two(self):
        self.manifest.write_text("invalid json")
        checked = self.cli("verify", self.project, self.manifest)
        self.assertEqual(checked.returncode, 2)
        self.assertIn("content_manifest:", checked.stderr)

    def test_cli_diff_between_versions(self):
        self.put("a", b"1")
        first = self.build()
        old = self.base / "old.json"
        cm._write_manifest(old, first)
        self.put("a", b"2")
        self.put("b", b"3")
        self.build()
        result = self.cli("diff", old, self.manifest)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["modified"], ["a"])
        self.assertEqual(json.loads(result.stdout)["added"], ["b"])

    def test_cli_nonexistent_root_exit_two(self):
        result = self.cli("build", self.base / "nope", "-o", self.manifest)
        self.assertEqual(result.returncode, 2)

    def test_manifest_never_contains_timestamp(self):
        self.put("a")
        self.build()
        self.assertNotIn("timestamp", self.manifest.read_text())
        self.assertNotIn("created_at", self.manifest.read_text())

    def test_sha256_is_lowercase(self):
        self.put("a")
        self.assertEqual(self.build()["files"][0]["sha256"], self.build()["files"][0]["sha256"].lower())

    @unittest.skipUnless(hasattr(os, "mkfifo"), "requires POSIX named pipes")
    def test_rejects_fifo(self):
        os.mkfifo(self.project / "pipe")
        with self.assertRaises(cm.ManifestError):
            self.build()


if __name__ == "__main__":
    unittest.main()