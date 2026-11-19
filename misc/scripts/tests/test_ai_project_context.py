"""Regression tests for read-only, bounded Godot AI context collection."""

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT.parent))
import ai_project_context as ctx


class ProjectContextTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.write("project.godot", '[application]\nconfig/name="Demo"\n')

    def write(self, path, content):
        target = self.root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content, encoding="utf-8")
        return target

    def test_empty_project(self):
        self.assertEqual(ctx.build_context(self.root)["files"], [])

    def test_schema_stable(self):
        self.assertEqual(ctx.build_context(self.root)["schema"], "cgame.ai_project_context.v1")

    def test_scene_nodes_and_references(self):
        self.write("scenes/main.tscn", '[gd_scene format=3]\n[ext_resource type="Script" path="res://scripts/player.gd" id="1"]\n[node name="Main" type="Node2D"]\n[node name="Player" type="CharacterBody2D" parent="."]\n')
        data = ctx.build_context(self.root)["files"][0]
        self.assertEqual(data["nodes"], [{"name": "Main", "type": "Node2D"}, {"name": "Player", "type": "CharacterBody2D", "parent": "."}])
        self.assertEqual(data["references"], ["res://scripts/player.gd"])

    def test_script_signatures_without_body(self):
        self.write("a.gd", 'class_name Hero\nextends Node2D\nvar api_key = "SECRET"\nfunc move(speed):\n  print("SECRET")\nstatic func jump():\n  pass\n')
        item = ctx.build_context(self.root)["files"][0]
        self.assertEqual(item["functions"], ["move", "jump"])
        self.assertEqual(item["class_name"], "Hero")
        self.assertEqual(item["extends"], "Node2D")
        self.assertNotIn("SECRET", json.dumps(item))

    def test_resource_type(self):
        self.write("item.tres", '[gd_resource type="Resource"]\n[sub_resource type="Gradient" id="G"]\n')
        self.assertEqual(ctx.build_context(self.root)["files"][0]["resource_types"], ["Gradient"])

    def test_shader_metadata_only(self):
        self.write("screen.gdshader", 'shader_type spatial;\n// secret_token=ABC\n')
        self.assertEqual(ctx.build_context(self.root)["files"][0], {"path": "screen.gdshader", "kind": "shader"})

    def test_sorted_and_deterministic(self):
        self.write("z.gd", "func z(): pass")
        self.write("a.gd", "func a(): pass")
        one = ctx.build_context(self.root)
        self.assertEqual(one, ctx.build_context(self.root))
        self.assertEqual([i["path"] for i in one["files"]], ["a.gd", "z.gd"])

    def test_hidden_and_import_cache_skipped(self):
        self.write(".godot/cache.gd", "func secret(): pass")
        self.write(".hidden.gd", "func secret(): pass")
        self.write("visible.gd", "func visible(): pass")
        self.assertEqual([i["path"] for i in ctx.build_context(self.root)["files"]], ["visible.gd"])

    def test_symlinked_file_skipped(self):
        outside = self.write("real.gd", "func hello(): pass")
        try:
            (self.root / "alias.gd").symlink_to(outside)
        except (NotImplementedError, OSError):
            self.skipTest("No symlink support")
        self.assertEqual([i["path"] for i in ctx.build_context(self.root)["files"]], ["real.gd"])

    def test_symlinked_directory_skipped(self):
        outside = self.root / "source"
        self.write("source/real.gd", "func hello(): pass")
        try:
            (self.root / "linked").symlink_to(outside, target_is_directory=True)
        except (NotImplementedError, OSError):
            self.skipTest("No symlink support")
        self.assertEqual([i["path"] for i in ctx.build_context(self.root)["files"]], ["source/real.gd"])

    def test_root_symlink_rejected(self):
        link = self.root.parent / (self.root.name + "-link")
        try:
            link.symlink_to(self.root, target_is_directory=True)
        except (NotImplementedError, OSError):
            self.skipTest("No symlink support")
        self.addCleanup(lambda: link.unlink(missing_ok=True))
        with self.assertRaises(ctx.ContextError):
            ctx.build_context(link)

    def test_project_manifest_symlink_rejected(self):
        manifest = self.root / "project.godot"
        manifest.unlink()
        outside = self.write("manifest.txt", "[application]")
        try:
            manifest.symlink_to(outside)
        except (NotImplementedError, OSError):
            self.skipTest("No symlink support")
        with self.assertRaises(ctx.ContextError):
            ctx.build_context(self.root)

    def test_missing_manifest_rejected(self):
        (self.root / "project.godot").unlink()
        with self.assertRaises(ctx.ContextError):
            ctx.build_context(self.root)

    def test_file_count_bound(self):
        for n in range(5):
            self.write(f"{n}.gd", "func hi(): pass")
        data = ctx.build_context(self.root, max_files=2)
        self.assertEqual(len(data["files"]), 2)
        self.assertEqual(data["skipped_files"], 3)
        self.assertTrue(data["truncated"])

    def test_file_byte_bound(self):
        self.write("large.gd", "x" * 128)
        self.assertEqual(ctx.build_context(self.root, max_file_bytes=32)["skipped_files"], 1)

    def test_invalid_utf8_skipped(self):
        (self.root / "bad.gd").write_bytes(b"\xff\xfe")
        self.assertEqual(ctx.build_context(self.root)["skipped_files"], 1)

    def test_binary_skipped(self):
        (self.root / "bad.gd").write_bytes(b"\x00binary")
        self.assertEqual(ctx.build_context(self.root)["skipped_files"], 1)

    def test_bounded_output(self):
        for n in range(30):
            self.write(f"{n:03}.gd", "\n".join(f"func function_{i}(): pass" for i in range(25)))
        result = ctx.build_context(self.root, max_output_bytes=600)
        self.assertTrue(result["truncated"])
        self.assertLessEqual(len(json.dumps(result, ensure_ascii=False, separators=(",", ":")).encode()), 600)

    def test_references_deduplicated_and_sorted(self):
        self.write("main.tscn", '\n'.join(f'[ext_resource type="Script" path="res://{x}" id="1"]' for x in ["b.gd", "a.gd", "b.gd"]))
        self.assertEqual(ctx.build_context(self.root)["files"][0]["references"], ["res://a.gd", "res://b.gd"])

    def test_reference_traversal_not_exported(self):
        self.write("main.tscn", '[ext_resource type="Script" path="res://../secret.gd" id="1"]')
        self.assertEqual(ctx.build_context(self.root)["files"][0]["references"], [])

    def test_limits_validation(self):
        for opts in ({"max_files": 0}, {"max_file_bytes": 0}, {"max_output_bytes": 511}, {"max_files": 10001}):
            with self.subTest(opts=opts), self.assertRaises(ctx.ContextError):
                ctx.build_context(self.root, **opts)

    def test_no_file_modification(self):
        path = self.write("player.gd", "func go(): pass")
        before = path.read_bytes()
        ctx.build_context(self.root)
        self.assertEqual(path.read_bytes(), before)

    def test_cli_valid_json(self):
        self.write("player.gd", "func go(): pass")
        proc = subprocess.run([sys.executable, str(ROOT.parent / "ai_project_context.py"), str(self.root)], capture_output=True, text=True, check=True)
        self.assertEqual(json.loads(proc.stdout)["files"][0]["path"], "player.gd")
        self.assertEqual(proc.stderr, "")

    def test_cli_invalid_project(self):
        proc = subprocess.run([sys.executable, str(ROOT.parent / "ai_project_context.py"), str(self.root / "missing")], capture_output=True, text=True)
        self.assertEqual(proc.returncode, 2)
        self.assertIn("project", proc.stderr.lower())


if __name__ == "__main__":
    unittest.main()
