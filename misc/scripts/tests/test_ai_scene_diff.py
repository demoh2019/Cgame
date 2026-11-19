"""Read-only, deterministic AI scene change previews and failure regressions."""

from __future__ import annotations

import contextlib
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from ai_scene_diff import SCHEMA, SceneDiffError, compare_projects, main
from scene_context_export import SceneContextError


ROOT = '[gd_scene format=3]\n[node name="Root" type="Node2D"]\n'


class SceneDiffTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        parent = Path(self.tmp.name)
        self.before = parent / "before"
        self.after = parent / "after"
        for path in (self.before, self.after):
            path.mkdir()
            (path / "project.godot").write_text('[application]\nconfig/name="Demo"\n', encoding="utf-8")
            (path / "main.tscn").write_text(ROOT, encoding="utf-8")

    def write(self, project, relative, content):
        path = project / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
        return path

    def diff(self, **kwargs):
        return compare_projects(self.before, self.after, "res://main.tscn", **kwargs)

    def test_identical_scene_zero_changes(self):
        result = self.diff()
        self.assertEqual(result["changes"], [])
        self.assertEqual(result["summary"]["total_changes"], 0)
        self.assertEqual(result["summary"]["text_changed_scenes"], 0)
        self.assertFalse(result["truncated"])

    def test_schema_and_summary(self):
        result = self.diff()
        self.assertEqual(result["schema"], SCHEMA)
        self.assertEqual(result["root_scene"], "res://main.tscn")
        self.assertEqual(result["summary"]["nodes_before"], 1)
        self.assertEqual(result["summary"]["nodes_after"], 1)
        self.assertEqual(result["summary"]["changes_reported"], 0)

    def test_added_node(self):
        self.write(self.after, "main.tscn", ROOT + '[node name="Enemy" type="Node2D" parent="."]\n')
        result = self.diff()
        self.assertEqual(result["summary"]["added_nodes"], 1)
        self.assertEqual(result["changes"][0]["after"]["name"], "Enemy")
        self.assertEqual(result["changes"][0]["action"], "added")

    def test_removed_node(self):
        self.write(self.before, "main.tscn", ROOT + '[node name="Old" type="Sprite2D" parent="."]\n')
        self.assertEqual(self.diff()["summary"]["removed_nodes"], 1)

    def test_modified_node_type(self):
        self.write(self.after, "main.tscn", ROOT.replace("Node2D", "Node3D"))
        report = self.diff()
        self.assertEqual(report["summary"]["modified_nodes"], 1)
        self.assertEqual(report["changes"][0]["before"]["type"], "Node2D")
        self.assertEqual(report["changes"][0]["after"]["type"], "Node3D")

    def test_renamed_node_is_remove_plus_add(self):
        self.write(self.after, "main.tscn", ROOT.replace("Root", "Renamed"))
        result = self.diff()["summary"]
        self.assertEqual(result["added_nodes"], 1)
        self.assertEqual(result["removed_nodes"], 1)
        self.assertEqual(result["modified_nodes"], 0)

    def test_reparent_is_remove_plus_add(self):
        original = ROOT + '[node name="Item" type="Node2D" parent="."]\n'
        self.write(self.before, "main.tscn", original)
        self.write(self.after, "main.tscn", original.replace('parent="."', 'parent="Other"'))
        result = self.diff()["summary"]
        self.assertEqual((result["added_nodes"], result["removed_nodes"]), (1, 1))

    def test_added_resource(self):
        self.write(self.after, "main.tscn", ROOT + '[ext_resource path="res://texture.png" type="Texture2D" id="1"]\n')
        report = self.diff()
        self.assertEqual(report["summary"]["added_resources"], 1)
        self.assertEqual(report["changes"][0]["after"]["path"], "res://texture.png")

    def test_removed_resource(self):
        self.write(self.before, "main.tscn", ROOT + '[ext_resource path="res://old.png" type="Texture2D" id="1"]\n')
        self.assertEqual(self.diff()["summary"]["removed_resources"], 1)

    def test_resource_type_change_is_add_and_remove(self):
        self.write(self.before, "main.tscn", ROOT + '[ext_resource path="res://resource.tres" type="Texture2D" id="1"]\n')
        self.write(self.after, "main.tscn", ROOT + '[ext_resource path="res://resource.tres" type="Resource" id="1"]\n')
        counts = self.diff()["summary"]
        self.assertEqual((counts["added_resources"], counts["removed_resources"]), (1, 1))

    def test_resource_identifier_only_change_is_ignored_structurally(self):
        self.write(self.before, "main.tscn", ROOT + '[ext_resource path="res://a.gd" type="Script" id="1"]\n')
        self.write(self.after, "main.tscn", ROOT + '[ext_resource path="res://a.gd" type="Script" id="2"]\n')
        report = self.diff()
        self.assertEqual(report["summary"]["total_changes"], 0)
        self.assertEqual(report["summary"]["text_changed_scenes"], 1)

    def test_only_property_change_reported_without_value(self):
        self.write(self.before, "main.tscn", ROOT + 'secret = "PRIVATE_PASSWORD_123"\n')
        self.write(self.after, "main.tscn", ROOT + 'secret = "PRIVATE_PASSWORD_456"\n')
        result = self.diff()
        self.assertEqual(result["summary"]["total_changes"], 0)
        self.assertEqual(result["text_changed_scenes"], ["res://main.tscn"])
        self.assertNotIn("PRIVATE_PASSWORD", json.dumps(result))

    def test_properties_are_never_returned_in_node_changes(self):
        self.write(self.after, "main.tscn", ROOT + '[node name="Added" type="Node2D" parent="."]\npassword="DO_NOT_DISCLOSE"\n')
        self.assertNotIn("DO_NOT_DISCLOSE", json.dumps(self.diff()))

    def test_moved_scene_adds_scene_and_nodes(self):
        self.write(self.after, "main.tscn", '[gd_scene format=3]\n'
                   '[ext_resource path="res://sub.tscn" type="PackedScene" id="scene"]\n'
                   '[node name="Root" type="Node2D"]\n')
        self.write(self.after, "sub.tscn", '[gd_scene format=3]\n[node name="Sub" type="Node3D"]\n')
        report = self.diff()
        self.assertEqual(report["summary"]["added_scenes"], 1)
        self.assertEqual(report["summary"]["added_nodes"], 1)
        self.assertEqual(report["summary"]["scenes_after"], 2)

    def test_removed_nested_scene(self):
        self.write(self.before, "main.tscn", '[gd_scene format=3]\n'
                   '[ext_resource path="res://sub.tscn" type="PackedScene" id="scene"]\n'
                   '[node name="Root" type="Node2D"]\n')
        self.write(self.before, "sub.tscn", '[gd_scene format=3]\n[node name="Sub" type="Node3D"]\n')
        report = self.diff()
        self.assertEqual(report["summary"]["removed_scenes"], 1)
        self.assertEqual(report["summary"]["removed_nodes"], 1)

    def test_nested_scene_change(self):
        for project in (self.before, self.after):
            self.write(project, "main.tscn", '[gd_scene format=3]\n'
                       '[ext_resource path="res://sub.tscn" id="s"]\n'
                       '[node name="Root" type="Node2D"]\n')
            self.write(project, "sub.tscn", ROOT)
        self.write(self.after, "sub.tscn", ROOT.replace("Node2D", "Node3D"))
        self.assertEqual(self.diff()["changes"][0]["scene"], "res://sub.tscn")

    def test_depth_zero_ignores_nested_scene(self):
        for project in (self.before, self.after):
            self.write(project, "main.tscn", '[gd_scene format=3]\n'
                       '[ext_resource path="res://sub.tscn" id="s"]\n'
                       '[node name="Root" type="Node2D"]\n')
        self.write(self.before, "sub.tscn", ROOT)
        self.write(self.after, "sub.tscn", ROOT.replace("Node2D", "Node3D"))
        self.assertEqual(self.diff(max_depth=0)["summary"]["total_changes"], 0)

    def test_missing_nested_scene_warning(self):
        self.write(self.after, "main.tscn", ROOT + '[ext_resource path="res://missing.tscn" id="x"]\n')
        self.assertEqual(self.diff()["warnings"]["after"][0]["scene"], "res://missing.tscn")

    def test_duplicate_node_identity_rejected(self):
        self.write(self.after, "main.tscn", ROOT + '[node name="Root" type="Control" parent=""]\n')
        with self.assertRaisesRegex(SceneDiffError, "duplicate"):
            self.diff()

    def test_truncation_count_preserved(self):
        self.write(self.after, "main.tscn", ROOT + "".join(
            f'[node name="N{i:03}" type="Node2D" parent="."]\n' for i in range(12)))
        report = self.diff(max_changes=3)
        self.assertTrue(report["truncated"])
        self.assertEqual(len(report["changes"]), 3)
        self.assertEqual(report["summary"]["changes_reported"], 3)
        self.assertEqual(report["summary"]["total_changes"], 12)

    def test_zero_max_changes_is_summary_only(self):
        self.write(self.after, "main.tscn", ROOT + '[node name="Added" type="Node2D" parent="."]\n')
        report = self.diff(max_changes=0)
        self.assertEqual(report["changes"], [])
        self.assertTrue(report["truncated"])
        self.assertEqual(report["summary"]["added_nodes"], 1)

    def test_bounded_output_byte_budget(self):
        self.write(self.after, "main.tscn", ROOT + "".join(
            f'[node name="Node{i:03}" type="Node2D" parent="."]\n' for i in range(50)))
        report = self.diff(max_output_bytes=1024)
        raw = json.dumps(report, ensure_ascii=False, separators=(",", ":"), sort_keys=True).encode()
        self.assertLessEqual(len(raw), 1024)
        self.assertTrue(report["truncated"])

    def test_large_diff_budget_matches_pop_one_reference(self):
        import copy
        self.write(self.after, "main.tscn", ROOT + "".join(
            f'[node name="Игрок_{i:03}" type="Node2D" parent="."]\n'
            for i in range(350)))
        complete = self.diff(max_changes=350, max_output_bytes=4 * 1024 * 1024)
        self.assertEqual(len(complete["changes"]), 350)
        for budget in (1024, 2048, 4096, 8192, 16384):
            with self.subTest(budget=budget):
                expected = copy.deepcopy(complete)

                def size():
                    return len(json.dumps(expected, ensure_ascii=False, sort_keys=True,
                                          separators=(",", ":")).encode("utf-8"))

                while expected["changes"] and size() > budget:
                    expected["changes"].pop()
                    expected["truncated"] = True
                    expected["summary"]["changes_reported"] = len(expected["changes"])
                if size() > budget:
                    with self.assertRaises(SceneDiffError):
                        self.diff(max_changes=350, max_output_bytes=budget)
                else:
                    self.assertEqual(self.diff(max_changes=350, max_output_bytes=budget),
                                     expected)

    def test_large_diff_budget_uses_logarithmic_json_checks(self):
        from unittest import mock
        import ai_scene_diff as diff_module
        self.write(self.after, "main.tscn", ROOT + "".join(
            f'[node name="N{i:03}" type="Node2D" parent="."]\n'
            for i in range(350)))
        original_dumps = json.dumps
        with mock.patch.object(diff_module.json, "dumps", wraps=original_dumps) as tracked:
            result = self.diff(max_changes=350, max_output_bytes=1024)
        self.assertTrue(result["truncated"])
        self.assertLessEqual(tracked.call_count, 16)

    def test_cli_respects_byte_budget(self):
        self.write(self.after, "main.tscn", ROOT + "".join(
            f'[node name="Node{i:03}" type="Node2D" parent="."]\n' for i in range(50)))
        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            result = main([str(self.before), str(self.after), "--scene", "res://main.tscn",
                           "--max-output-bytes", "1024"])
        self.assertEqual(result, 0)
        self.assertLessEqual(len(stdout.getvalue().encode("utf-8")), 1024)
        self.assertTrue(json.loads(stdout.getvalue())["truncated"])

    def test_invalid_preview_limits(self):
        for opts in ({"max_changes": -1}, {"max_changes": 10001},
                     {"max_output_bytes": 1023}, {"max_output_bytes": 4 * 1024 * 1024 + 1}):
            with self.subTest(opts=opts), self.assertRaises(SceneDiffError):
                self.diff(**opts)

    def test_invalid_exporter_limits(self):
        for opts in ({"max_depth": -1}, {"max_scenes": 0},
                     {"max_nodes": 0}, {"max_scene_bytes": 0}):
            with self.subTest(opts=opts), self.assertRaises(SceneContextError):
                self.diff(**opts)

    def test_symlinked_scene_rejected(self):
        (self.after / "main.tscn").unlink()
        try:
            (self.after / "main.tscn").symlink_to(self.before / "main.tscn")
        except (NotImplementedError, OSError):
            self.skipTest("Symlinks unsupported")
        with self.assertRaisesRegex(SceneContextError, "Symlinked"):
            self.diff()

    def test_symlinked_project_root_rejected(self):
        alias = self.before.parent / "alias"
        try:
            alias.symlink_to(self.before, target_is_directory=True)
        except (NotImplementedError, OSError):
            self.skipTest("Symlinks unsupported")
        with self.assertRaises(SceneDiffError):
            compare_projects(alias, self.after, "res://main.tscn")

    def test_missing_after_project_rejected(self):
        with self.assertRaises(SceneDiffError):
            compare_projects(self.before, self.after / "missing", "res://main.tscn")

    def test_symlink_project_config_rejected(self):
        (self.after / "project.godot").unlink()
        try:
            (self.after / "project.godot").symlink_to(self.before / "project.godot")
        except (NotImplementedError, OSError):
            self.skipTest("Symlinks unsupported")
        with self.assertRaises(SceneDiffError):
            self.diff()

    def test_path_traversal_rejected(self):
        with self.assertRaises(SceneContextError):
            compare_projects(self.before, self.after, "res://../evil.tscn")

    def test_missing_main_scene_rejected(self):
        (self.after / "main.tscn").unlink()
        with self.assertRaisesRegex(SceneContextError, "root scene"):
            self.diff()

    def test_scene_byte_budget(self):
        self.write(self.after, "main.tscn", ROOT + "x" * 1000)
        with self.assertRaisesRegex(SceneContextError, "byte limit"):
            self.diff(max_scene_bytes=50)

    def test_node_budget(self):
        self.write(self.after, "main.tscn", ROOT + '[node name="Other" type="Node2D" parent="."]\n')
        with self.assertRaisesRegex(SceneContextError, "node count"):
            self.diff(max_nodes=1)

    def test_no_files_modified(self):
        before = (self.before / "main.tscn").read_bytes()
        after = (self.after / "main.tscn").read_bytes()
        self.diff()
        self.assertEqual((self.before / "main.tscn").read_bytes(), before)
        self.assertEqual((self.after / "main.tscn").read_bytes(), after)

    def test_deterministic_json(self):
        self.write(self.after, "main.tscn", ROOT + '[node name="Enemy" type="Node2D" parent="."]\n')
        first = json.dumps(self.diff(), ensure_ascii=False, sort_keys=True)
        self.assertEqual(first, json.dumps(self.diff(), ensure_ascii=False, sort_keys=True))

    def test_unicode_node_names(self):
        self.write(self.after, "main.tscn", ROOT + '[node name="Игрок 🚀" type="Node2D" parent="."]\n')
        report = self.diff()
        self.assertEqual(report["changes"][0]["after"]["name"], "Игрок 🚀")

    def test_cli_success(self):
        capture = io.StringIO()
        with contextlib.redirect_stdout(capture):
            result = main([str(self.before), str(self.after), "--scene", "res://main.tscn"])
        self.assertEqual(result, 0)
        self.assertEqual(json.loads(capture.getvalue())["schema"], SCHEMA)

    def test_cli_failure_does_not_output_json(self):
        stdout, stderr = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            result = main([str(self.before), str(self.after), "--scene", "res://missing.tscn"])
        self.assertEqual(result, 2)
        self.assertEqual(stdout.getvalue(), "")
        self.assertIn("root scene", stderr.getvalue())

    def test_cli_summary_only(self):
        self.write(self.after, "main.tscn", ROOT + '[node name="New" type="Node2D" parent="."]\n')
        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            result = main([str(self.before), str(self.after), "--scene", "res://main.tscn", "--max-changes", "0"])
        self.assertEqual(result, 0)
        report = json.loads(stdout.getvalue())
        self.assertEqual(report["changes"], [])
        self.assertEqual(report["summary"]["total_changes"], 1)


if __name__ == "__main__":
    unittest.main()
