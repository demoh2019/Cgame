"""Asset size map regression tests; no Godot binary required."""

import contextlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import asset_size_map as size_map


class AssetSizeMapTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name) / "game"
        self.root.mkdir()
        self.put("project.godot", b"")

    def put(self, name, content=b"abc"):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
        return path

    def scan(self):
        return size_map.scan_project(self.root)

    def report(self, **kwargs):
        return size_map.build_report(self.scan(), **kwargs)

    def cli(self, *args):
        return subprocess.run([sys.executable, size_map.__file__, str(self.root), *args],
                              text=True, capture_output=True, check=False)

    def test_empty_project_marker_counted(self):
        self.assertEqual(self.report()["file_count"], 1)
        self.assertEqual(self.report()["total_bytes"], 0)

    def test_sorted_relative_paths(self):
        self.put("z/file.txt")
        self.put("a/file.png")
        self.assertEqual([a["path"] for a in self.scan()],
                         ["a/file.png", "project.godot", "z/file.txt"])

    def test_extension_grouping_and_casefold(self):
        self.put("one.PNG", b"abc")
        self.put("two.png", b"xy")
        png = next(v for v in self.report()["by_extension"] if v["extension"] == ".png")
        self.assertEqual(png, {"extension": ".png", "files": 2, "bytes": 5})

    def test_extensionless_file(self):
        self.put("LICENSE", b"abc")
        self.assertTrue(any(group["extension"] == "(none)" for group in self.report()["by_extension"]))

    def test_largest_files_sorted_by_size(self):
        self.put("small", b"a")
        self.put("large", b"aaaa")
        self.assertEqual(self.report(top=1)["largest_files"], [{"path": "large", "bytes": 4}])

    def test_ties_use_path_order(self):
        self.put("z", b"x")
        self.put("a", b"y")
        self.assertEqual([v["path"] for v in self.report(top=2)["largest_files"]], ["a", "z"])

    def test_top_zero(self):
        self.assertEqual(self.report(top=0)["largest_files"], [])

    def test_negative_or_huge_top_rejected(self):
        for top in (-1, 1001):
            with self.subTest(top=top), self.assertRaises(size_map.AssetSizeError):
                size_map.build_report(self.scan(), top=top)

    def test_generated_directories_excluded(self):
        for folder in size_map.EXCLUDED_DIRECTORIES:
            self.put(folder + "/hidden.bin", b"xxxxxxxx")
        self.assertEqual(self.report()["file_count"], 1)

    def test_total_budget_violation(self):
        self.put("a", b"1234")
        self.assertEqual(self.report(total_limit=3)["violations"],
                         [{"rule": "total", "actual": 4, "limit": 3}])

    def test_file_budget_violation(self):
        self.put("a", b"1234")
        self.assertEqual(self.report(file_limit=3)["violations"],
                         [{"rule": "file", "path": "a", "actual": 4, "limit": 3}])

    def test_extension_budget_violation(self):
        self.put("a.png", b"1234")
        self.assertEqual(self.report(extension_limits={".png": 3})["violations"],
                         [{"rule": "extension", "extension": ".png", "actual": 4, "limit": 3}])

    def test_equal_budget_allowed(self):
        self.put("a.png", b"1234")
        self.assertEqual(self.report(total_limit=4, file_limit=4,
                                     extension_limits={".png": 4})["violations"], [])

    def test_zero_budget_flags_files(self):
        self.put("a", b"x")
        self.assertEqual(len(self.report(total_limit=0, file_limit=0)["violations"]), 2)

    def test_multiple_violation_order(self):
        self.put("z.png", b"aaa")
        self.put("a.png", b"bb")
        violations = self.report(total_limit=1, extension_limits={".png": 1}, file_limit=1)["violations"]
        self.assertEqual([v["rule"] for v in violations], ["total", "extension", "file", "file"])
        self.assertEqual([v["path"] for v in violations[2:]], ["a.png", "z.png"])

    def test_missing_extension_budget_no_violation(self):
        self.assertEqual(self.report(extension_limits={".png": 0})["violations"], [])

    def test_negative_budget_rejected(self):
        with self.assertRaises(size_map.AssetSizeError):
            size_map.build_report(self.scan(), total_limit=-1)

    def test_boolean_budget_rejected(self):
        with self.assertRaises(size_map.AssetSizeError):
            size_map.build_report(self.scan(), file_limit=True)

    def test_limit_parser_normalizes_case(self):
        self.assertEqual(size_map.parse_extension_limits([".PNG=17", "(none)=0"]),
                         {".png": 17, "(none)": 0})

    def test_limit_parser_rejects_duplicates(self):
        with self.assertRaises(size_map.AssetSizeError):
            size_map.parse_extension_limits([".png=1", ".PNG=2"])

    def test_limit_parser_rejects_invalid_specification(self):
        for item in ("png=1", ".png", ".png=-1", ".png=1.5", ".png= 1", "../a=1", ".png=١"):
            with self.subTest(item=item), self.assertRaises(size_map.AssetSizeError):
                size_map.parse_extension_limits([item])

    def test_cli_json_success(self):
        self.put("a.png", b"abc")
        result = self.cli("--format", "json", "--extension-limit", ".png=3")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["total_bytes"], 3)

    def test_cli_budget_failure(self):
        self.put("a.png", b"abc")
        result = self.cli("--format", "json", "--total-limit", "2")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(json.loads(result.stdout)["violations"][0]["rule"], "total")

    def test_cli_invalid_limit_exit_two(self):
        self.assertEqual(self.cli("--total-limit", "-1").returncode, 2)
        self.assertEqual(self.cli("--extension-limit", "broken").returncode, 2)

    def test_cli_text_output(self):
        self.put("a.png", b"abc")
        self.assertIn("Largest assets:", self.cli("--format", "text").stdout)

    def test_cli_error_for_missing_root(self):
        self.assertEqual(size_map.main([str(self.root / "missing")]), 2)

    def test_scan_rejects_missing_project_marker(self):
        (self.root / "project.godot").unlink()
        with self.assertRaises(size_map.AssetSizeError):
            self.scan()

    def test_scan_rejects_symlinked_file(self):
        target = self.put("target")
        try:
            (self.root / "alias").symlink_to(target)
        except (NotImplementedError, OSError):
            self.skipTest("Symlink creation unavailable")
        with self.assertRaises(size_map.AssetSizeError):
            self.scan()

    def test_scan_rejects_symlinked_directory(self):
        external = self.root.parent / "external"
        external.mkdir()
        try:
            (self.root / "linked").symlink_to(external, target_is_directory=True)
        except (NotImplementedError, OSError):
            self.skipTest("Symlink creation unavailable")
        with self.assertRaises(size_map.AssetSizeError):
            self.scan()

    def test_scan_rejects_symlinked_root(self):
        try:
            linked = self.root.parent / "linked"
            linked.symlink_to(self.root, target_is_directory=True)
        except (NotImplementedError, OSError):
            self.skipTest("Symlink creation unavailable")
        with self.assertRaises(size_map.AssetSizeError):
            size_map.scan_project(linked)

    def test_scan_rejects_case_collisions(self):
        self.put("Atlas.png")
        self.put("atlas.png")
        if len(list(self.root.glob("*.png"))) < 2:
            self.skipTest("Case-insensitive filesystem")
        with self.assertRaises(size_map.AssetSizeError):
            self.scan()

    def test_scan_rejects_directory_case_collisions(self):
        self.put("Images/a.png")
        self.put("images/b.png")
        if len(list(self.root.iterdir())) < 3:
            self.skipTest("Case-insensitive filesystem")
        with self.assertRaises(size_map.AssetSizeError):
            self.scan()

    def test_repeatable_output(self):
        self.put("z.mp3", b"abc")
        self.assertEqual(json.dumps(self.report(), sort_keys=True), json.dumps(self.report(), sort_keys=True))

    @unittest.skipUnless(hasattr(os, "mkfifo"), "Requires POSIX FIFOs")
    def test_scan_rejects_special_file(self):
        os.mkfifo(self.root / "pipe")
        with self.assertRaises(size_map.AssetSizeError):
            self.scan()

    def test_top_k_matches_full_sort_on_large_deterministic_dataset(self):
        entries = [
            {"path": f"assets/{i:05d}.png", "extension": ".png",
             "bytes": (i * 37 + i // 17) % 1009}
            for i in range(6000)
        ]
        baseline = sorted(entries, key=lambda a: (-a["bytes"], a["path"]))
        for k in (0, 1, 7, 100, 999, 1000):
            with self.subTest(top=k):
                expected = [{"path": item["path"], "bytes": item["bytes"]}
                            for item in baseline[:k]]
                self.assertEqual(size_map.build_report(entries, top=k)["largest_files"],
                                 expected)

    def test_deep_directory_paths_are_scanned_and_sorted(self):
        for i in range(80):
            self.put(f"scenes/levels/rooms/room_{i:03d}.tscn", bytes([i]) * (i % 7))
        self.assertEqual(self.report()["file_count"], 81)
        self.assertEqual(len(self.report(top=10)["largest_files"]), 10)

    def test_empty_directory_case_collision_is_detected(self):
        (self.root / "EmptyFolder").mkdir()
        (self.root / "emptyfolder").mkdir(exist_ok=True)
        if len([p for p in self.root.iterdir() if p.name.casefold() == "emptyfolder"]) < 2:
            self.skipTest("Case-insensitive filesystem")
        with self.assertRaises(size_map.AssetSizeError):
            self.scan()

    def test_file_and_directory_name_collision(self):
        self.put("folder", b"x")
        try:
            (self.root / "FOLDER").mkdir()
        except FileExistsError:
            self.skipTest("Case-insensitive filesystem")
        if not (self.root / "folder").is_file() or not (self.root / "FOLDER").is_dir():
            self.skipTest("Case-insensitive filesystem")
        with self.assertRaises(size_map.AssetSizeError):
            self.scan()



if __name__ == "__main__":
    unittest.main()
