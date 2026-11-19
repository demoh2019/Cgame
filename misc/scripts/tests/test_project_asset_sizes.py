"""Regression tests for a deterministic project source-asset size report."""

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import project_asset_sizes as sizes


class AssetSizeTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name) / "game"
        self.root.mkdir()

    def put(self, name, data=b"1"):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        return path

    def cli(self, *args):
        return subprocess.run([sys.executable, sizes.__file__, str(self.root), *args],
                              capture_output=True, text=True)

    def test_empty(self):
        report = sizes.scan(self.root)
        self.assertEqual(report["summary"], {"files": 0, "total_bytes": 0})
        self.assertEqual(report["largest"], [])
        self.assertEqual(report["by_extension"], {})

    def test_directory_and_extension_aggregates(self):
        self.put("sprites/hero.PNG", b"abcd")
        self.put("sprites/other.png", b"ef")
        self.put("main.tscn", b"123")
        report = sizes.scan(self.root)
        self.assertEqual(report["summary"], {"files": 3, "total_bytes": 9})
        self.assertEqual(report["by_extension"][".png"], {"files": 2, "bytes": 6})
        self.assertEqual(report["by_directory"]["sprites"], {"files": 2, "bytes": 6})
        self.assertEqual(report["by_directory"]["[root]"], {"files": 1, "bytes": 3})

    def test_no_extension(self):
        self.put("LICENSE", b"abc")
        self.assertEqual(sizes.scan(self.root)["by_extension"]["[none]"]["bytes"], 3)

    def test_largest_sorted_by_size_then_path(self):
        self.put("z.png", b"12")
        self.put("a.png", b"12")
        self.put("b.wav", b"123")
        self.assertEqual([x["path"] for x in sizes.scan(self.root, top=2)["largest"]], ["b.wav", "a.png"])

    def test_determinism(self):
        self.put("c/file", b"123")
        self.put("a", b"z")
        first = json.dumps(sizes.scan(self.root), sort_keys=True)
        self.assertEqual(first, json.dumps(sizes.scan(self.root), sort_keys=True))

    def test_generated_directories_ignored(self):
        for ignored in sizes.SKIP_DIRS:
            self.put(f"{ignored}/cached.bin", b"123456")
        self.assertEqual(sizes.scan(self.root)["summary"]["files"], 0)

    def test_normal_hidden_files_included(self):
        self.put(".gdignore", b"hi")
        self.assertEqual(sizes.scan(self.root)["summary"]["files"], 1)

    def test_exact_budget_passes(self):
        self.put("size.txt", b"1234")
        self.assertEqual(sizes.scan(self.root, max_total=4, max_file=4)["violations"], [])

    def test_both_budget_violations(self):
        self.put("x.bin", b"1234")
        self.put("z.bin", b"123")
        result = sizes.scan(self.root, max_total=6, max_file=3)
        self.assertEqual([v["kind"] for v in result["violations"]], ["total", "file"])
        self.assertEqual(result["violations"][1]["path"], "x.bin")

    def test_multiple_file_violations_are_ranked(self):
        self.put("a", b"1" * 3)
        self.put("b", b"1" * 4)
        self.assertEqual([v["path"] for v in sizes.scan(self.root, max_file=2)["violations"]], ["b", "a"])

    def test_large_top_matches_full_sort_reference(self):
        for i in range(230):
            self.put(f"assets/{i:04d}.png", b"x" * ((i * 31 + i // 9) % 37))
        files = [(f"assets/{i:04d}.png", (i * 31 + i // 9) % 37)
                 for i in range(230)]
        oracle = sorted(files, key=lambda item: (-item[1], item[0]))
        for top in (0, 1, 3, 20, 100, 230, 500):
            with self.subTest(top=top):
                self.assertEqual(
                    sizes.scan(self.root, top=top)["largest"],
                    [{"path": p, "bytes": n} for p, n in oracle[:top]],
                )

    def test_violation_order_is_full_sort_filtered_by_budget(self):
        for i in range(90):
            self.put(f"data/{i:03d}.bin", b"x" * ((i * 13) % 19))
        ordered = sorted(
            ((f"data/{i:03d}.bin", (i * 13) % 19) for i in range(90)),
            key=lambda item: (-item[1], item[0]),
        )
        for limit in (0, 2, 8, 17, 18, 19, 200):
            with self.subTest(limit=limit):
                report = sizes.scan(self.root, top=7, max_file=limit)
                expected = [
                    {"kind": "file", "path": path, "bytes": count, "limit_bytes": limit}
                    for path, count in ordered if count > limit
                ]
                self.assertEqual(report["violations"], expected)
                self.assertEqual(report["largest"],
                                 [{"path": p, "bytes": n} for p, n in ordered[:7]])

    def test_zero_top(self):
        self.put("asset", b"123")
        self.assertEqual(sizes.scan(self.root, top=0)["largest"], [])

    def test_negative_programmatic_limits(self):
        for kwargs in ({"top": -1}, {"max_total": -1}, {"max_file": -1}):
            with self.subTest(kwargs=kwargs), self.assertRaises(sizes.AssetSizeError):
                sizes.scan(self.root, **kwargs)

    def test_missing_root(self):
        with self.assertRaises(sizes.AssetSizeError):
            sizes.scan(self.root / "missing")

    def test_symlink_file_rejected(self):
        target = self.put("a")
        try:
            (self.root / "shortcut").symlink_to(target)
        except OSError:
            self.skipTest("symlinks unavailable")
        with self.assertRaises(sizes.AssetSizeError):
            sizes.scan(self.root)

    def test_symlink_directory_rejected(self):
        target = self.root / "data"
        target.mkdir()
        try:
            (self.root / "alias").symlink_to(target, target_is_directory=True)
        except OSError:
            self.skipTest("symlinks unavailable")
        with self.assertRaises(sizes.AssetSizeError):
            sizes.scan(self.root)

    def test_symlink_root_rejected(self):
        alias = self.root.parent / "alias"
        try:
            alias.symlink_to(self.root, target_is_directory=True)
        except OSError:
            self.skipTest("symlinks unavailable")
        with self.assertRaises(sizes.AssetSizeError):
            sizes.scan(alias)

    def test_fifo_rejected(self):
        import os
        if not hasattr(os, "mkfifo"):
            self.skipTest("named pipes unavailable")
        os.mkfifo(self.root / "pipe")
        with self.assertRaises(sizes.AssetSizeError):
            sizes.scan(self.root)

    def test_cli_json_report_success(self):
        self.put("one.png", b"abc")
        result = self.cli("--top", "1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["largest"], [{"path": "one.png", "bytes": 3}])

    def test_cli_fail_on_budget(self):
        self.put("big", b"x" * 1025)
        result = self.cli("--max-file-mib", "0.0001")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(json.loads(result.stdout)["violations"][0]["kind"], "file")

    def test_cli_rejects_bad_budget(self):
        for invalid in ("nan", "inf", "-1", "garbage", "1e308"):
            with self.subTest(value=invalid):
                self.assertEqual(self.cli("--max-total-mib", invalid).returncode, 2)

    def test_cli_rejects_negative_top(self):
        self.assertEqual(self.cli("--top", "-1").returncode, 2)

    def test_parse_budget_exact_mib(self):
        self.assertEqual(sizes.parse_mib("1.5"), 1572864)

    def test_unicode_paths(self):
        self.put("декорации/雪.png", b"12")
        self.assertEqual(sizes.scan(self.root)["largest"][0]["path"], "декорации/雪.png")

    def test_walk_errors_not_silently_ignored(self):
        def fail_walk(root, *, followlinks, onerror):
            onerror(PermissionError("denied"))
            yield str(root), [], []
        with patch.object(sizes.os, "walk", side_effect=fail_walk):
            with self.assertRaises(sizes.AssetSizeError):
                sizes.scan(self.root)


if __name__ == "__main__":
    unittest.main()
