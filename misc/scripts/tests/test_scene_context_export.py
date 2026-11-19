"""Offline, deterministic regression coverage for scene-aware AI context."""

from __future__ import annotations

import contextlib
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from scene_context_export import (SceneContextError, attributes, export_context,
                                  main, parse_scene, safe_path)


class SceneContextTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        (self.root / "project.godot").write_text('[application]\nconfig/name="Demo"\n', encoding="utf-8")

    def write(self, path, contents):
        target = self.root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(contents, encoding="utf-8")
        return target

    def basic(self):
        self.write("main.tscn", '''[gd_scene format=3]
[ext_resource type="Script" path="res://player.gd" id="script"]
[ext_resource type="PackedScene" path="res://sub/child.tscn" id="child"]
[node name="Root" type="Node2D"]
[node name="Child" parent="." instance=ExtResource("child")]
text = "SUPER_SECRET_TOKEN=never_include"
''')
        self.write("sub/child.tscn", '[gd_scene format=3]\n[node name="Nested" type="Node2D"]\n')
        return export_context(self.root, "res://main.tscn")

    def test_extracts_nodes_without_properties(self):
        data = self.basic()
        self.assertEqual(data["summary"], {"scenes": 2, "nodes": 3, "external_resources": 2})
        self.assertEqual(data["scenes"][0]["nodes"][1]["instance_scene"], "res://sub/child.tscn")
        self.assertNotIn("SUPER_SECRET_TOKEN", json.dumps(data))

    def test_scene_sort_stable(self):
        self.assertEqual([s["path"] for s in self.basic()["scenes"]],
                         ["res://main.tscn", "res://sub/child.tscn"])

    def test_depth_zero_only_root(self):
        self.basic()
        self.assertEqual(export_context(self.root, "res://main.tscn", max_depth=0)["summary"]["scenes"], 1)

    def test_depth_one_nested_scene(self):
        self.basic()
        self.assertEqual(export_context(self.root, "res://main.tscn", max_depth=1)["summary"]["scenes"], 2)

    def test_missing_dependency_warning(self):
        self.write("main.tscn", '[gd_scene format=3]\n[ext_resource path="res://missing.tscn" type="PackedScene" id="x"]\n')
        data = export_context(self.root, "res://main.tscn")
        self.assertEqual(data["summary"]["scenes"], 1)
        self.assertEqual(data["warnings"][0]["scene"], "res://missing.tscn")

    def test_missing_root_fails(self):
        with self.assertRaisesRegex(SceneContextError, "root scene"):
            export_context(self.root, "res://missing.tscn")

    def test_symlink_is_blocked(self):
        self.basic()
        (self.root / "alias.tscn").symlink_to(self.root / "main.tscn")
        with self.assertRaisesRegex(SceneContextError, "Symlinked"):
            export_context(self.root, "res://alias.tscn")

    def test_symlinked_directory_is_blocked(self):
        self.basic()
        (self.root / "alias").symlink_to(self.root / "sub", target_is_directory=True)
        with self.assertRaisesRegex(SceneContextError, "Symlinked"):
            safe_path(self.root, "res://alias/child.tscn")

    def test_traversal_is_blocked(self):
        for uri in ("res://../a.tscn", "res://a/../b.tscn", "res:///a.tscn", "res://./x.tscn", "res://a//b.tscn"):
            with self.subTest(uri=uri), self.assertRaises(SceneContextError):
                safe_path(self.root, uri)

    def test_non_res_scheme_rejected(self):
        for uri in ("https://foo/bar.tscn", "file:///etc/passwd", "uid://123"):
            with self.subTest(uri=uri), self.assertRaises(SceneContextError):
                safe_path(self.root, uri)

    def test_backslash_and_control_character_rejected(self):
        for uri in ("res://a\\b.tscn", "res://a\x00b.tscn", "res://a\nb.tscn", "res://c:b.tscn"):
            with self.subTest(uri=uri), self.assertRaises(SceneContextError):
                safe_path(self.root, uri)

    def test_rejects_non_scene_extension(self):
        with self.assertRaisesRegex(SceneContextError, "Only .tscn"):
            export_context(self.root, "res://script.gd")

    def test_requires_project_config(self):
        (self.root / "project.godot").unlink()
        with self.assertRaisesRegex(SceneContextError, "project.godot"):
            export_context(self.root, "res://main.tscn")

    def test_rejects_invalid_limits(self):
        self.basic()
        for kwargs in (dict(max_depth=-1), dict(max_scenes=0), dict(max_nodes=0), dict(max_scene_bytes=0)):
            with self.subTest(kwargs=kwargs), self.assertRaises(SceneContextError):
                export_context(self.root, "res://main.tscn", **kwargs)

    def test_scene_count_budget(self):
        self.basic()
        with self.assertRaisesRegex(SceneContextError, "Scene count"):
            export_context(self.root, "res://main.tscn", max_scenes=1)

    def test_node_budget(self):
        self.basic()
        with self.assertRaisesRegex(SceneContextError, "node count"):
            export_context(self.root, "res://main.tscn", max_nodes=2)

    def test_file_bytes_budget(self):
        self.basic()
        with self.assertRaisesRegex(SceneContextError, "byte limit"):
            export_context(self.root, "res://main.tscn", max_scene_bytes=4)

    def test_nested_large_file_warning(self):
        self.basic()
        data = export_context(self.root, "res://main.tscn", max_scene_bytes=500)
        self.assertEqual(data["summary"]["scenes"], 2)
        self.write("sub/child.tscn", 'x' * 600)
        data = export_context(self.root, "res://main.tscn", max_scene_bytes=500)
        self.assertEqual(data["summary"]["scenes"], 1)
        self.assertIn("byte limit", data["warnings"][0]["reason"])

    def test_invalid_utf8_nested_scene_warning(self):
        self.basic()
        (self.root / "sub/child.tscn").write_bytes(b'\xff')
        data = export_context(self.root, "res://main.tscn")
        self.assertEqual(data["summary"]["scenes"], 1)
        self.assertEqual(len(data["warnings"]), 1)

    def test_invalid_scene_header(self):
        self.write("main.tscn", "[gd_resource type=\"Resource\"]")
        with self.assertRaisesRegex(SceneContextError, "Not a Godot"):
            export_context(self.root, "res://main.tscn")

    def test_empty_scene(self):
        self.write("main.tscn", "   \n")
        with self.assertRaisesRegex(SceneContextError, "Empty"):
            export_context(self.root, "res://main.tscn")

    def test_attributes_escaped_quotes(self):
        self.assertEqual(attributes('name="Player \\"One\\"" type="Node2D"')["name"], 'Player "One"')

    def test_invalid_escaped_header_is_rejected(self):
        with self.assertRaises(SceneContextError):
            attributes('name="bad\\q"')

    def test_uid_reference_not_resolved(self):
        data = parse_scene('[gd_scene format=3]\n[ext_resource path="uid://abc" type="PackedScene" id="x"]', "res://main.tscn")
        self.assertEqual(data["resources"][0]["status"], "unresolved")

    def test_relative_scene_reference_resolved(self):
        self.write("sub/main.tscn", '[gd_scene format=3]\n[ext_resource path="child.tscn" type="PackedScene" id="x"]')
        self.write("sub/child.tscn", '[gd_scene format=3]\n')
        self.assertEqual(export_context(self.root, "res://sub/main.tscn")["summary"]["scenes"], 2)

    def test_relative_reference_cannot_escape(self):
        data = parse_scene('[gd_scene format=3]\n[ext_resource path="../../outside.tscn" id="x"]', 'res://sub/main.tscn')
        self.assertEqual(data["resources"][0]["status"], "unresolved")

    def test_absolute_external_scheme_unresolved(self):
        data = parse_scene('[gd_scene format=3]\n[ext_resource path="https://example.com/evil.tscn" id="x"]', 'res://main.tscn')
        self.assertEqual(data["resources"][0]["status"], "unresolved")

    def test_duplicate_nested_scene_indexed_once(self):
        self.write("main.tscn", '[gd_scene format=3]\n[ext_resource path="res://sub.tscn" id="a"]\n[ext_resource path="res://sub.tscn" id="b"]')
        self.write("sub.tscn", '[gd_scene format=3]\n')
        self.assertEqual(export_context(self.root, "res://main.tscn")["summary"]["scenes"], 2)

    def test_many_shared_edges_and_cycle(self):
        # Hundreds of duplicate dependencies should not blow up the BFS queue.
        duplicates = "\n".join(
            f'[ext_resource path="res://shared.tscn" id="{i}"]'
            for i in range(500)
        )
        self.write("main.tscn", "[gd_scene format=3]\n" + duplicates + "\n")
        self.write("shared.tscn",
                   '[gd_scene format=3]\n[ext_resource path="res://main.tscn" id="loop"]\n')
        data = export_context(self.root, "res://main.tscn", max_depth=100, max_scenes=2)
        self.assertEqual(data["summary"]["scenes"], 2)
        self.assertEqual(data["summary"]["external_resources"], 501)
        self.assertEqual(data["warnings"], [])

    def test_cycle_is_bounded(self):
        self.write("main.tscn", '[gd_scene format=3]\n[ext_resource path="res://sub.tscn" id="a"]')
        self.write("sub.tscn", '[gd_scene format=3]\n[ext_resource path="res://main.tscn" id="a"]')
        self.assertEqual(export_context(self.root, "res://main.tscn", max_depth=50)["summary"]["scenes"], 2)

    def test_unicode_node_names(self):
        self.write("main.tscn", '[gd_scene format=3]\n[node name="Игрок 🚀" type="Node3D"]')
        data = export_context(self.root, "res://main.tscn")
        self.assertEqual(data["scenes"][0]["nodes"][0]["name"], "Игрок 🚀")

    def test_cli_json(self):
        self.basic()
        capture = io.StringIO()
        with contextlib.redirect_stdout(capture):
            result = main([str(self.root), "--scene", "res://main.tscn"])
        self.assertEqual(result, 0)
        self.assertEqual(json.loads(capture.getvalue())["summary"]["nodes"], 3)

    def test_cli_failure(self):
        capture = io.StringIO()
        with contextlib.redirect_stderr(capture):
            result = main([str(self.root), "--scene", "res://missing.tscn"])
        self.assertEqual(result, 2)
        self.assertIn("root scene", capture.getvalue())

    def test_deterministic_json(self):
        self.basic()
        first = json.dumps(export_context(self.root, "res://main.tscn"), sort_keys=True)
        self.assertEqual(first, json.dumps(export_context(self.root, "res://main.tscn"), sort_keys=True))


if __name__ == "__main__":
    unittest.main()
