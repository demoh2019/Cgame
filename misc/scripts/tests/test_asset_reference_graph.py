#!/usr/bin/env python3
"""Offline regression tests for asset dependency and reverse-reference tracing."""

from __future__ import annotations

from contextlib import redirect_stderr, redirect_stdout
from io import StringIO
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from asset_reference_graph import (  # noqa: E402
    build_graph, main, to_dot, to_json, to_text, trace_references,
)


class AssetReferenceGraphTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    def write(self, relative, content=""):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        if isinstance(content, bytes):
            path.write_bytes(content)
        else:
            path.write_text(content, encoding="utf-8")
        return path

    def graph(self, **kwargs):
        return build_graph(self.root, **kwargs)

    def selected(self, asset, direction="both", depth=1, **kwargs):
        return trace_references(self.graph(**kwargs), asset, direction, depth)

    def cli(self, *args):
        out, err = StringIO(), StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            exit_code = main([str(self.root), *args])
        return exit_code, out.getvalue(), err.getvalue()

    def test_empty_project_graph(self):
        self.assertEqual(self.graph().nodes, ())
        self.assertEqual(self.graph().references, ())

    def test_unreferenced_binary_asset_can_be_selected(self):
        self.write("art/sprite.png", b"PNG")
        result = self.selected("res://art/sprite.png")
        self.assertEqual(result.nodes, ("art/sprite.png",))
        self.assertEqual(result.references, ())

    def test_direct_dependencies(self):
        self.write("art/tex.png", b"PNG")
        self.write("scene.tscn", 'path="res://art/tex.png"')
        result = self.selected("scene.tscn", "dependencies")
        self.assertEqual(result.nodes, ("art/tex.png", "scene.tscn"))
        self.assertEqual([(r.source, r.target, r.line) for r in result.references],
                         [("scene.tscn", "art/tex.png", 1)])

    def test_direct_referencers(self):
        self.write("tex.png", b"PNG")
        self.write("a.tscn", 'path="res://tex.png"')
        self.write("b.tres", 'path="res://tex.png"')
        result = self.selected("tex.png", "referencers")
        self.assertEqual(result.nodes, ("a.tscn", "b.tres", "tex.png"))

    def test_direction_filters_out_other_side(self):
        self.write("child.gd", 'preload("res://leaf.tres")')
        self.write("leaf.tres")
        self.write("parent.tscn", 'path="res://child.gd"')
        self.assertEqual(self.selected("child.gd", "dependencies").nodes,
                         ("child.gd", "leaf.tres"))
        self.assertEqual(self.selected("child.gd", "referencers").nodes,
                         ("child.gd", "parent.tscn"))
        self.assertEqual(self.selected("child.gd").nodes,
                         ("child.gd", "leaf.tres", "parent.tscn"))

    def test_depth_zero_only_selected_node(self):
        self.write("a.gd", 'load("res://b.gd")')
        self.write("b.gd")
        result = self.selected("a.gd", depth=0)
        self.assertEqual(result.nodes, ("a.gd",))
        self.assertEqual(result.references, ())

    def test_two_hop_dependency_traversal(self):
        self.write("a.gd", 'load("res://b.gd")')
        self.write("b.gd", 'load("res://c.gd")')
        self.write("c.gd")
        self.assertEqual(self.selected("a.gd", "dependencies", 1).nodes, ("a.gd", "b.gd"))
        self.assertEqual(self.selected("a.gd", "dependencies", 2).nodes,
                         ("a.gd", "b.gd", "c.gd"))

    def test_two_hop_reverse_traversal(self):
        self.write("a.gd", 'load("res://b.gd")')
        self.write("b.gd", 'load("res://c.gd")')
        self.write("c.gd")
        self.assertEqual(self.selected("c.gd", "referencers", 2).nodes,
                         ("a.gd", "b.gd", "c.gd"))

    def test_unlimited_traversal(self):
        for i in range(12):
            self.write(f"{i}.gd", f'load("res://{i+1}.gd")')
        self.write("12.gd")
        self.assertEqual(len(self.selected("0.gd", "dependencies", -1).nodes), 13)

    def test_cycle_terminates(self):
        self.write("a.gd", 'load("res://b.gd")')
        self.write("b.gd", 'load("res://a.gd")')
        result = self.selected("a.gd", "both", -1)
        self.assertEqual(len(result.nodes), 2)
        self.assertEqual(len(result.references), 2)

    def test_self_reference_safe(self):
        self.write("self.gd", 'load("res://self.gd")')
        self.assertEqual(len(self.selected("self.gd", depth=-1).references), 1)

    def test_independent_assets_not_in_subgraph(self):
        self.write("a.gd", 'load("res://b.gd")')
        self.write("b.gd")
        self.write("other.gd", 'load("res://extra.tres")')
        self.write("extra.tres")
        self.assertEqual(self.selected("a.gd", depth=-1).nodes, ("a.gd", "b.gd"))

    def test_duplicate_occurrences_preserve_line_numbers(self):
        self.write("a.gd", 'load("res://b.gd")\nload("res://b.gd")')
        self.write("b.gd")
        result = self.selected("a.gd")
        self.assertEqual([r.line for r in result.references], [1, 2])
        self.assertEqual(to_dot(result).count('"res://a.gd" -> "res://b.gd";'), 1)

    def test_missing_references_omitted_not_invented(self):
        self.write("a.gd", 'load("res://missing.tres")')
        self.assertEqual(self.selected("a.gd").nodes, ("a.gd",))
        self.assertEqual(self.graph().references, ())

    def test_wrong_case_is_not_a_valid_edge(self):
        self.write("Textures/Hero.PNG", b"png")
        self.write("main.gd", 'load("res://textures/hero.png")')
        self.assertEqual(self.selected("main.gd").nodes, ("main.gd",))

    def test_parent_traversal_and_absolute_paths_not_in_graph(self):
        self.write("main.gd", 'load("res://../secret.gd")\nload("res:///etc/passwd")')
        self.assertEqual(self.selected("main.gd").references, ())

    def test_cache_directories_ignored(self):
        self.write(".godot/generated.gd", 'load("res://main.gd")')
        self.write(".git/meta.gd", 'load("res://main.gd")')
        self.write("main.gd", 'load("res://.godot/generated.gd")')
        self.assertEqual(self.graph().nodes, ("main.gd",))
        self.assertEqual(self.graph().references, ())

    def test_exclude_applies_to_source_and_target(self):
        self.write("vendor/external.tres")
        self.write("vendor/ignored.gd", 'load("res://main.gd")')
        self.write("main.gd", 'load("res://vendor/external.tres")')
        self.assertEqual(self.graph(exclude=("vendor/*",)).nodes, ("main.gd",))
        self.assertEqual(self.graph(exclude=("vendor/*",)).references, ())

    def test_symlink_file_ignored(self):
        if not hasattr(os, "symlink"):
            self.skipTest("Symlinks unsupported")
        self.write("target.gd")
        try:
            (self.root / "alias.gd").symlink_to(self.root / "target.gd")
        except OSError:
            self.skipTest("Insufficient symlink privileges")
        self.write("main.gd", 'load("res://alias.gd")')
        self.assertEqual(self.graph().nodes, ("main.gd", "target.gd"))
        self.assertEqual(self.graph().references, ())

    def test_external_symlink_not_followed(self):
        if not hasattr(os, "symlink"):
            self.skipTest("Symlinks unsupported")
        with tempfile.TemporaryDirectory() as outside:
            external = Path(outside) / "external.gd"
            external.write_text("test", encoding="utf-8")
            try:
                (self.root / "external.gd").symlink_to(external)
            except OSError:
                self.skipTest("Insufficient symlink privileges")
            self.write("main.gd", 'load("res://external.gd")')
            self.assertEqual(self.graph().nodes, ("main.gd",))
            self.assertEqual(self.graph().references, ())

    def test_nested_directory_symlink_not_traversed(self):
        if not hasattr(os, "symlink"):
            self.skipTest("Symlinks unsupported")
        with tempfile.TemporaryDirectory() as outside:
            Path(outside, "secret.gd").write_text("test", encoding="utf-8")
            try:
                (self.root / "external").symlink_to(outside, target_is_directory=True)
            except OSError:
                self.skipTest("Insufficient symlink privileges")
            self.write("main.gd", 'load("res://external/secret.gd")')
            self.assertEqual(self.graph().nodes, ("main.gd",))

    def test_invalid_utf8_source_skipped(self):
        self.write("invalid.gd", b"\xff")
        self.write("valid.gd")
        self.assertEqual(self.graph().nodes, ("invalid.gd", "valid.gd"))
        self.assertEqual(self.graph().references, ())

    def test_large_source_skipped(self):
        self.write("a.gd", 'load("res://b.gd")')
        self.write("b.gd")
        self.assertEqual(self.graph(max_text_bytes=5).references, ())

    def test_shader_include_reference(self):
        self.write("shader.gdshader", '#include "res://shared.gdshaderinc"')
        self.write("shared.gdshaderinc")
        self.assertEqual(len(self.selected("shader.gdshader").references), 1)

    def test_gdscript_comments_do_not_add_edges(self):
        self.write("a.gd", '# load("res://b.gd")\nvar x = 1 # load("res://b.gd")')
        self.write("b.gd")
        self.assertEqual(self.graph().references, ())

    def test_unquoted_prose_is_not_reference(self):
        self.write("a.gd", 'var a = "see res://b.gd for information"')
        self.write("b.gd")
        self.assertEqual(self.graph().references, ())

    def test_json_output_contains_line_metadata(self):
        self.write("a.gd", 'load("res://b.tres")')
        self.write("b.tres")
        data = json.loads(to_json(self.selected("a.gd"), "a.gd", "both", 1))
        self.assertEqual(data["summary"], {"assets": 2, "references": 1})
        self.assertEqual(data["references"], [{"source": "res://a.gd", "target": "res://b.tres", "line": 1}])
        self.assertEqual(data["asset"], "res://a.gd")

    def test_dot_direction_and_deterministic_output(self):
        self.write("a.gd", 'load("res://b.tres")')
        self.write("b.tres")
        result = self.selected("a.gd")
        first = to_dot(result)
        self.assertEqual(first, to_dot(result))
        self.assertIn("rankdir=LR;", first)
        self.assertIn('"res://a.gd" -> "res://b.tres";', first)
        self.assertNotIn('"res://b.tres" -> "res://a.gd";', first)

    def test_dot_escapes_quotes_and_backslashes(self):
        self.write('s"cene.gd')
        self.write("back\\slash.gd")
        result = self.graph()
        dot = to_dot(result)
        self.assertIn('s\\"cene.gd', dot)
        self.assertIn('back\\\\slash.gd', dot)

    def test_unicode_paths_retained(self):
        self.write("текстура.png", b"PNG")
        self.write("сцена.tscn", 'path="res://текстура.png"')
        data = json.loads(to_json(self.selected("текстура.png"), "текстура.png", "referencers", 1))
        self.assertEqual(len(data["nodes"]), 2)
        self.assertIn("res://текстура.png", data["nodes"])

    def test_text_report_includes_source_line(self):
        self.write("a.gd", '\nload("res://b.tres")')
        self.write("b.tres")
        text = to_text(self.selected("a.gd"), "a.gd")
        self.assertIn("res://a.gd:2 -> res://b.tres", text)

    def test_text_report_with_no_edges(self):
        self.write("alone.tres")
        self.assertIn("No static references", to_text(self.selected("alone.tres"), "alone.tres"))

    def test_invalid_root(self):
        with self.assertRaises(ValueError):
            build_graph(self.root / "not-here")

    def test_invalid_size(self):
        with self.assertRaises(ValueError):
            self.graph(max_text_bytes=0)

    def test_invalid_asset(self):
        with self.assertRaisesRegex(ValueError, "Asset not found"):
            trace_references(self.graph(), "res://missing.gd")

    def test_invalid_direction(self):
        self.write("a.gd")
        with self.assertRaises(ValueError):
            trace_references(self.graph(), "a.gd", "sideways")

    def test_invalid_depth(self):
        self.write("a.gd")
        with self.assertRaises(ValueError):
            trace_references(self.graph(), "a.gd", depth=-2)

    def test_cli_json(self):
        self.write("a.gd", 'load("res://b.tres")')
        self.write("b.tres")
        code, out, err = self.cli("--asset", "res://b.tres", "--direction", "referencers", "--format", "json")
        self.assertEqual(code, 0, err)
        self.assertEqual(json.loads(out)["summary"]["references"], 1)

    def test_cli_dot(self):
        self.write("a.gd")
        code, out, err = self.cli("--asset", "a.gd", "--format", "dot")
        self.assertEqual(code, 0, err)
        self.assertTrue(out.startswith("digraph AssetReferences {"))

    def test_cli_invalid_missing_asset_returns_two(self):
        code, out, err = self.cli("--asset", "res://missing.gd")
        self.assertEqual(code, 2)
        self.assertEqual(out, "")
        self.assertIn("Asset not found", err)

    def test_cli_negative_depth_returns_two(self):
        self.write("a.gd")
        code, _, err = self.cli("--asset", "a.gd", "--depth", "-2")
        self.assertEqual(code, 2)
        self.assertIn("depth", err)

    def test_cli_invalid_max_size_returns_two(self):
        self.write("a.gd")
        code, _, err = self.cli("--asset", "a.gd", "--max-text-bytes", "0")
        self.assertEqual(code, 2)
        self.assertIn("max_text_bytes", err)

    def test_deterministic_across_repeated_builds(self):
        self.write("z.gd", 'load("res://a.gd")')
        self.write("a.gd", 'load("res://b.tres")')
        self.write("b.tres")
        self.assertEqual(self.graph(), self.graph())


if __name__ == "__main__":
    unittest.main()
