"""Regression tests for incremental content bundles (Python standard library)."""
import hashlib
import json
from pathlib import Path
import os
import subprocess
import sys
import tempfile
import unittest
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import content_delta_bundle as delta


def snapshot(files):
    return {"format": 1, "files": [{"path": name, "bytes": len(data),
            "sha256": hashlib.sha256(data).hexdigest()} for name, data in sorted(files.items())]}


class DeltaBundleTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "game"
        self.root.mkdir()
        self.output = Path(self.temp.name) / "changes.zip"
        self.old = snapshot({"old": b"same", "changed": b"old", "removed": b"gone"})
        self.new = snapshot({"old": b"same", "changed": b"new", "added": b"fresh"})
        for row in self.new["files"]:
            value = {"old": b"same", "changed": b"new", "added": b"fresh"}[row["path"]]
            (self.root / row["path"]).write_bytes(value)

    def build(self, old=None, new=None):
        return delta.build_bundle(old or self.old, new or self.new, self.root, self.output)

    def test_only_modified_and_new_are_included(self):
        self.assertEqual(self.build(), {"packed": 2, "bytes": 8})
        with zipfile.ZipFile(self.output) as archive:
            self.assertEqual(archive.namelist(), ["added", "changed"])
            self.assertEqual(archive.read("added"), b"fresh")
            self.assertEqual(archive.read("changed"), b"new")

    def test_verify_good_bundle(self):
        self.build()
        self.assertEqual(delta.verify_bundle(self.old, self.new, self.output), {"verified": 2})

    def test_deterministic_rebuild(self):
        self.build()
        first = self.output.read_bytes()
        self.build()
        self.assertEqual(self.output.read_bytes(), first)

    def test_reproducible_across_file_timestamps(self):
        self.build()
        first = self.output.read_bytes()
        os.utime(self.root / "added", (1000000000, 1000000000))
        self.build()
        self.assertEqual(self.output.read_bytes(), first)

    def test_deletion_is_manifest_only(self):
        self.build()
        with zipfile.ZipFile(self.output) as archive:
            self.assertNotIn("removed", archive.namelist())

    def test_no_changes_produces_empty_valid_archive(self):
        result = self.build(self.new, self.new)
        self.assertEqual(result, {"packed": 0, "bytes": 0})
        self.assertEqual(delta.verify_bundle(self.new, self.new, self.output), {"verified": 0})

    def test_missing_source_is_rejected_and_keeps_previous_bundle(self):
        self.build()
        old_zip = self.output.read_bytes()
        (self.root / "added").unlink()
        with self.assertRaises(FileNotFoundError):
            self.build()
        self.assertEqual(self.output.read_bytes(), old_zip)

    def test_modified_source_does_not_overwrite_previous_bundle(self):
        self.build()
        previous = self.output.read_bytes()
        (self.root / "changed").write_bytes(b"tampered")
        with self.assertRaises(delta.DeltaBundleError):
            self.build()
        self.assertEqual(self.output.read_bytes(), previous)

    def test_reject_symlink_file(self):
        (self.root / "added").unlink()
        (self.root / "added").symlink_to(self.root / "old")
        with self.assertRaises(delta.DeltaBundleError):
            self.build()

    def test_reject_symlink_parent(self):
        sub = self.root / "dir"
        sub.mkdir()
        (sub / "a").write_bytes(b"x")
        manifest = snapshot({"dir/a": b"x"})
        sub.rename(self.root / "real")
        sub.symlink_to(self.root / "real", target_is_directory=True)
        with self.assertRaises(delta.DeltaBundleError):
            self.build(snapshot({}), manifest)

    def test_reject_output_aliasing_source_file(self):
        with self.assertRaises(delta.DeltaBundleError):
            delta.build_bundle(self.old, self.new, self.root, self.root / "added")

    def test_reject_wrong_content_hash_on_verification(self):
        self.build()
        with zipfile.ZipFile(self.output, "w") as archive:
            archive.writestr("added", b"false")
            archive.writestr("changed", b"new")
        with self.assertRaises(delta.DeltaBundleError):
            delta.verify_bundle(self.old, self.new, self.output)

    def test_reject_missing_member(self):
        with zipfile.ZipFile(self.output, "w") as archive:
            archive.writestr("added", b"fresh")
        with self.assertRaises(delta.DeltaBundleError):
            delta.verify_bundle(self.old, self.new, self.output)

    def test_reject_extra_member(self):
        with zipfile.ZipFile(self.output, "w") as archive:
            archive.writestr("added", b"fresh")
            archive.writestr("changed", b"new")
            archive.writestr("extra", b"unexpected")
        with self.assertRaises(delta.DeltaBundleError):
            delta.verify_bundle(self.old, self.new, self.output)

    def test_reject_duplicate_member(self):
        import warnings
        with zipfile.ZipFile(self.output, "w") as archive, warnings.catch_warnings():
            warnings.simplefilter("ignore", UserWarning)
            archive.writestr("added", b"fresh")
            archive.writestr("added", b"fresh")
        with self.assertRaises(delta.DeltaBundleError):
            delta.verify_bundle(self.old, self.new, self.output)

    def test_reject_unsorted_members(self):
        with zipfile.ZipFile(self.output, "w") as archive:
            archive.writestr("changed", b"new")
            archive.writestr("added", b"fresh")
        with self.assertRaises(delta.DeltaBundleError):
            delta.verify_bundle(self.old, self.new, self.output)

    def test_reject_compressed_member(self):
        with zipfile.ZipFile(self.output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            archive.writestr("added", b"fresh")
            archive.writestr("changed", b"new")
        with self.assertRaises(delta.DeltaBundleError):
            delta.verify_bundle(self.old, self.new, self.output)

    def test_reject_symlink_archive_member(self):
        with zipfile.ZipFile(self.output, "w") as archive:
            member = zipfile.ZipInfo("added")
            member.create_system = 3
            member.external_attr = 0o120777 << 16
            archive.writestr(member, b"fresh")
            archive.writestr("changed", b"new")
        with self.assertRaises(delta.DeltaBundleError):
            delta.verify_bundle(self.old, self.new, self.output)

    def test_reject_different_manifest(self):
        self.build()
        modified = snapshot({"old": b"same", "changed": b"new2", "added": b"fresh"})
        with self.assertRaises(delta.DeltaBundleError):
            delta.verify_bundle(self.old, modified, self.output)

    def test_binary_nested_and_unicode_paths(self):
        self.root.joinpath("assets").mkdir()
        self.root.joinpath("assets", "café.bin").write_bytes(bytes(range(256)))
        updated = snapshot({"assets/café.bin": bytes(range(256))})
        self.build(snapshot({}), updated)
        self.assertEqual(delta.verify_bundle(snapshot({}), updated, self.output), {"verified": 1})

    def test_cli_end_to_end(self):
        old_path = Path(self.temp.name) / "old.json"
        new_path = Path(self.temp.name) / "new.json"
        old_path.write_text(json.dumps(self.old))
        new_path.write_text(json.dumps(self.new))
        script = str(Path(delta.__file__))
        build = subprocess.run([sys.executable, script, "build", str(old_path), str(new_path), str(self.root), "-o", str(self.output)], capture_output=True, text=True)
        self.assertEqual(build.returncode, 0, build.stderr)
        verify = subprocess.run([sys.executable, script, "verify", str(old_path), str(new_path), str(self.output)], capture_output=True, text=True)
        self.assertEqual(verify.returncode, 0, verify.stderr)
        self.assertEqual(json.loads(verify.stdout), {"verified": 2})

    def test_cli_bad_manifest_has_nonzero_exit_code(self):
        old_path = Path(self.temp.name) / "old.json"
        old_path.write_text("{broken")
        new_path = Path(self.temp.name) / "new.json"
        new_path.write_text(json.dumps(self.new))
        p = subprocess.run([sys.executable, str(Path(delta.__file__)), "build", str(old_path), str(new_path), str(self.root), "-o", str(self.output)], capture_output=True, text=True)
        self.assertNotEqual(p.returncode, 0)
        self.assertFalse(self.output.exists())


if __name__ == "__main__":
    unittest.main()
