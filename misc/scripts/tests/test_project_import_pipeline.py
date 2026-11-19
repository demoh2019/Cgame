#!/usr/bin/env python3
"""Regression tests for content-hash-driven Godot import orchestration."""

import json
import hashlib
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from project_import_pipeline import (  # noqa: E402
    CACHE_VERSION, STATE_NAME, ImportPipelineError, inventory, load_state,
    make_plan, run_pipeline, save_state,
)


class ImportPipelineTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.write("project.godot", "config_version=5\n")
        self.calls = []
        self.version = "4.7.2.stable"
        self.exit_code = 0

    def write(self, name, content):
        file = self.root / name
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_text(content, encoding="utf-8")
        return file

    def runner(self, command, **kwargs):
        self.calls.append(command)
        if command[-1] == "--version":
            return subprocess.CompletedProcess(command, 0, stdout=self.version + "\n")
        self.assertEqual(command[-1], "--import")
        self.assertIn("--headless", command)
        (self.root / ".godot").mkdir(exist_ok=True)
        return subprocess.CompletedProcess(command, self.exit_code)

    def pipeline(self, **kwargs):
        return run_pipeline(self.root, godot="fake-godot", runner=self.runner, **kwargs)

    def test_first_run_imports_and_writes_state(self):
        result = self.pipeline()
        self.assertEqual(result["status"], "imported")
        self.assertEqual(len(self.calls), 2)
        self.assertEqual(load_state(self.root / ".godot" / STATE_NAME)["engine"], self.version)

    def test_unchanged_files_skip_second_import(self):
        self.pipeline()
        result = self.pipeline()
        self.assertEqual(result["status"], "skipped")
        self.assertEqual(len(self.calls), 3)

    def test_warm_run_skips_source_hashing(self):
        self.write("textures/large.png", "a" * 25000)
        self.pipeline()
        with patch("project_import_pipeline.hashlib.sha256", wraps=hashlib.sha256) as sha:
            result = self.pipeline()
        self.assertEqual(result["status"], "skipped")
        self.assertEqual(sha.call_count, 0)

    def test_verify_all_disables_metadata_cache(self):
        self.write("level.tscn", "[gd_scene format=3]")
        self.pipeline()
        with patch("project_import_pipeline.hashlib.sha256", wraps=hashlib.sha256) as sha:
            self.assertEqual(self.pipeline(verify_all=True)["status"], "skipped")
        self.assertEqual(sha.call_count, 2)  # project.godot + level.tscn

    def test_metadata_cached_file_uses_sha_of_original(self):
        asset = self.write("texture.bin", "abcdef")
        self.pipeline()
        recorded = load_state(self.root / ".godot" / STATE_NAME)
        self.assertEqual(recorded["files"]["texture.bin"],
                         hashlib.sha256(asset.read_bytes()).hexdigest())
        self.assertEqual(len(recorded["file_stats"]["texture.bin"]), 6)

    def test_touch_without_content_change_refreshes_metadata(self):
        self.write("scene.tscn", "[gd_scene format=3]")
        self.pipeline()
        entry = self.root / "scene.tscn"
        modified = entry.stat().st_mtime_ns + 10_000_000_000
        os.utime(entry, ns=(modified, modified))
        self.assertEqual(self.pipeline()["status"], "skipped")
        with patch("project_import_pipeline.hashlib.sha256", wraps=hashlib.sha256) as sha:
            self.assertEqual(self.pipeline()["status"], "skipped")
        self.assertEqual(sha.call_count, 0)

    def test_invalid_metadata_cache_is_rejected(self):
        self.pipeline()
        state_path = self.root / ".godot" / STATE_NAME
        state = json.loads(state_path.read_text(encoding="utf-8"))
        state["file_stats"]["project.godot"][2] = "broken"
        state_path.write_text(json.dumps(state), encoding="utf-8")
        self.assertIsNone(load_state(state_path))
        self.assertIn("missing_state", self.pipeline()["reasons"])

    def test_existing_source_change_during_import_rejected(self):
        self.write("player.gd", "before")
        def mutate(command, **kwargs):
            if command[-1] == "--version":
                return subprocess.CompletedProcess(command, 0, stdout="4.7.2.stable\n")
            self.write("player.gd", "AFTER!")
            return subprocess.CompletedProcess(command, 0)
        with self.assertRaisesRegex(ImportPipelineError, "changed during import"):
            run_pipeline(self.root, runner=mutate)
        self.assertFalse((self.root / ".godot" / STATE_NAME).exists())

    def test_change_same_size_is_not_skipped(self):
        self.write("a.gd", "one")
        self.pipeline()
        self.write("a.gd", "two")
        result = self.pipeline()
        self.assertEqual(result["changed"], ["a.gd"])
        self.assertEqual(result["status"], "imported")

    def test_added_file(self):
        self.pipeline()
        self.write("new.tscn", "[gd_scene]\n")
        self.assertEqual(self.pipeline()["added"], ["new.tscn"])

    def test_removed_file(self):
        self.write("old.gd", "pass")
        self.pipeline()
        (self.root / "old.gd").unlink()
        self.assertEqual(self.pipeline()["removed"], ["old.gd"])

    def test_engine_version_invalidates_cache(self):
        self.pipeline()
        self.version = "4.8"
        result = self.pipeline()
        self.assertIn("engine_changed", result["reasons"])
        self.assertEqual(result["status"], "imported")

    def test_force_invalidates(self):
        self.pipeline()
        self.assertIn("forced", self.pipeline(force=True)["reasons"])

    def test_dry_run_does_not_modify_state(self):
        result = self.pipeline(dry_run=True)
        self.assertEqual(result["status"], "dry_run")
        self.assertEqual(len(self.calls), 1)
        self.assertFalse((self.root / ".godot").exists())

    def test_missing_cache_directory_invalidates(self):
        self.pipeline()
        import shutil
        shutil.rmtree(self.root / ".godot")
        self.assertIn("missing_godot_cache", self.pipeline()["reasons"])

    def test_failed_import_does_not_record_cache(self):
        self.exit_code = 1
        with self.assertRaises(ImportPipelineError):
            self.pipeline()
        self.assertIsNone(load_state(self.root / ".godot" / STATE_NAME))

    def test_failed_version_does_not_import(self):
        def fail(command, **kwargs):
            return subprocess.CompletedProcess(command, 1, stdout="")
        with self.assertRaises(ImportPipelineError):
            run_pipeline(self.root, runner=fail)

    def test_exception_from_editor_does_not_write_state(self):
        def fail(command, **kwargs):
            if command[-1] == "--version":
                return subprocess.CompletedProcess(command, 0, stdout="4.7")
            raise subprocess.TimeoutExpired(command, 1)
        with self.assertRaises(ImportPipelineError):
            run_pipeline(self.root, runner=fail)
        self.assertFalse((self.root / ".godot" / STATE_NAME).exists())

    def test_corrupt_state_forces_import(self):
        self.write(".godot/" + STATE_NAME, "{broken")
        self.assertIn("missing_state", self.pipeline()["reasons"])

    def test_obsolete_schema_forces_import(self):
        self.write(".godot/" + STATE_NAME, json.dumps({"schema": 0, "files": {}, "engine": "4.7"}))
        self.assertIn("missing_state", self.pipeline()["reasons"])

    def test_state_sha_validation(self):
        path = self.write(".godot/" + STATE_NAME,
                          json.dumps({"schema": CACHE_VERSION, "files": {"a": "invalid"}, "engine": "4.7"}))
        self.assertIsNone(load_state(path))

    def test_ignore_cache_and_vcs(self):
        self.write(".git/a.gd", "bad")
        self.write(".godot/generated.txt", "cache")
        self.write("textures/a.png.import", "config")
        self.assertEqual(sorted(inventory(self.root)), ["project.godot", "textures/a.png.import"])

    def test_deterministic_inventory(self):
        self.write("z.gd", "pass")
        self.write("a.tscn", "[gd_scene]")
        self.assertEqual(list(inventory(self.root)), ["a.tscn", "project.godot", "z.gd"])
        self.assertEqual(inventory(self.root), inventory(self.root))

    def test_missing_project(self):
        (self.root / "project.godot").unlink()
        with self.assertRaises(ImportPipelineError):
            inventory(self.root)

    def test_symlink_file_rejected(self):
        try:
            (self.root / "link.gd").symlink_to(self.root / "project.godot")
        except (NotImplementedError, OSError):
            self.skipTest("Symlink unavailable")
        with self.assertRaises(ImportPipelineError):
            inventory(self.root)

    def test_symlink_directory_rejected(self):
        self.write("real/asset.txt", "a")
        try:
            (self.root / "linked").symlink_to(self.root / "real", target_is_directory=True)
        except (NotImplementedError, OSError):
            self.skipTest("Symlink unavailable")
        with self.assertRaises(ImportPipelineError):
            inventory(self.root)

    def test_cache_path_symlink_rejected(self):
        outside = self.root / "target"
        outside.mkdir()
        try:
            (self.root / ".godot").symlink_to(outside, target_is_directory=True)
        except (NotImplementedError, OSError):
            self.skipTest("Symlink unavailable")
        with self.assertRaises(ImportPipelineError):
            self.pipeline()

    def test_negative_timeout_rejected(self):
        with self.assertRaises(ImportPipelineError):
            self.pipeline(timeout=0)

    def test_unicode_paths(self):
        self.write("мир/лес.gd", "pass")
        self.assertIn("мир/лес.gd", inventory(self.root))

    def test_plan_diff_sorted(self):
        before = {"schema": CACHE_VERSION, "engine": "4", "files": {"b": "a"*64, "a": "b"*64}}
        current = {"c": "c"*64, "b": "b"*64}
        result = make_plan(current, before, "4", True)
        self.assertEqual(result["added"], ["c"])
        self.assertEqual(result["changed"], ["b"])
        self.assertEqual(result["removed"], ["a"])

    def test_save_state_roundtrip(self):
        files, file_stats = inventory(self.root, include_metadata=True)
        state = {"schema": CACHE_VERSION, "files": files,
                 "file_stats": file_stats, "engine": "4"}
        path = self.root / ".godot" / STATE_NAME
        save_state(path, state)
        self.assertEqual(load_state(path), state)

    def test_state_does_not_write_on_race(self):
        def mutate(command, **kwargs):
            if command[-1] == "--version":
                return subprocess.CompletedProcess(command, 0, stdout="4")
            self.write("late.gd", "pass")
            return subprocess.CompletedProcess(command, 0)
        with self.assertRaisesRegex(ImportPipelineError, "changed during import"):
            run_pipeline(self.root, runner=mutate)
        self.assertFalse((self.root / ".godot" / STATE_NAME).exists())

    def test_dry_run_with_existing_state(self):
        self.pipeline()
        result = self.pipeline(dry_run=True)
        self.assertFalse(result["needs_import"])

    def test_two_runs_have_stable_engine_id(self):
        self.pipeline()
        first = load_state(self.root / ".godot" / STATE_NAME)
        self.pipeline()
        second = load_state(self.root / ".godot" / STATE_NAME)
        self.assertEqual(first, second)

    def test_hash_detects_binary_bytes(self):
        path = self.root / "image.png"
        path.write_bytes(b"\x00\xff\x80")
        a = inventory(self.root)["image.png"]
        path.write_bytes(b"\x00\xff\x81")
        self.assertNotEqual(inventory(self.root)["image.png"], a)


if __name__ == "__main__":
    unittest.main()
