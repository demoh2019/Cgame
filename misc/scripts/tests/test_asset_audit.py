"""Self-contained tests for the asset pipeline preflight checker."""

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
import asset_audit as audit


class AssetAuditTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "project"
        self.root.mkdir()
        self.put("project.godot", '[application]\nrun/main_scene="res://main.tscn"\n')
        self.put("main.tscn", '[gd_scene format=3]\n')

    def put(self, path, content=""):
        p = self.root / path
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(content, encoding="utf-8")
        return p

    def report(self, **kwargs):
        return audit.audit_project(self.root, **kwargs)

    def codes(self, **kwargs):
        return [finding.code for finding in self.report(**kwargs).findings]

    def test_clean_project(self):
        r = self.report()
        self.assertEqual(r.files, 2)
        self.assertEqual(r.references, 1)
        self.assertEqual(r.findings, [])

    def test_project_root_required(self):
        (self.root / "project.godot").unlink()
        with self.assertRaisesRegex(ValueError, "No project.godot"):
            self.report()

    def test_missing_directory(self):
        with self.assertRaisesRegex(ValueError, "does not exist"):
            audit.audit_project(self.root / "absent")

    def test_unreadable_directory_fails_instead_of_silently_skipping(self):
        def broken_walk(root, *, followlinks, onerror):
            self.assertFalse(followlinks)
            self.assertTrue(callable(onerror))
            yield str(root), [], ["project.godot", "main.tscn"]
            onerror(PermissionError("cannot read nested directory"))

        with patch.object(audit.os, "walk", side_effect=broken_walk):
            with self.assertRaisesRegex(ValueError, "Cannot enumerate all project files"):
                self.report()

    def test_cli_rejects_incomplete_scan(self):
        def broken_walk(root, *, followlinks, onerror):
            onerror(PermissionError("incomplete file tree"))
            yield str(root), [], []

        with patch.object(audit.os, "walk", side_effect=broken_walk):
            with contextlib.redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit) as result:
                    audit.main([str(self.root)])
        self.assertEqual(result.exception.code, 2)

    def test_missing_resource(self):
        self.put("main.tscn", '[ext_resource type="Script" path="res://missing.gd" id="1"]')
        self.assertIn("MISSING_RESOURCE", self.codes())

    def test_missing_scene_main_scene(self):
        (self.root / "main.tscn").unlink()
        self.assertEqual(self.codes(), ["MISSING_RESOURCE"])

    def test_scene_external_dependency(self):
        self.put("main.tscn", '[ext_resource type="Script" path="res://scripts/actor.gd" id="1"]')
        self.put("scripts/actor.gd", "extends Node\n")
        r = self.report()
        self.assertEqual(r.findings, [])
        self.assertEqual(r.graph["main.tscn"], ["scripts/actor.gd"])

    def test_resource_external_dependency(self):
        self.put("material.tres", '[ext_resource type="Texture" path="res://textures/a.png" id="1"]')
        self.put("textures/a.png", "bytes")
        self.assertEqual(self.report().findings, [])
        self.assertIn("material.tres", self.report().graph)

    def test_script_preload_dependency(self):
        self.put("main.gd", 'const X = preload("res://main.tscn")\n')
        self.assertEqual(self.report().graph["main.gd"], ["main.tscn"])

    def test_script_load_dependency(self):
        self.put("main.gd", 'var x = load("res://data/nope.tres")\n')
        self.assertIn("MISSING_RESOURCE", self.codes())

    def test_single_quotes(self):
        self.put("main.gd", "const X = preload('res://main.tscn')\n")
        self.assertEqual(self.report().references, 2)

    def test_whitespace_calls(self):
        self.put("main.gd", 'const X = preload  (  "res://main.tscn" )\n')
        self.assertEqual(self.report().references, 2)

    def test_ignores_gd_comment(self):
        self.put("main.gd", '# preload("res://not_found.tscn")\n')
        self.assertEqual(self.report().findings, [])

    def test_ignores_shader_comment(self):
        self.put("effect.gdshader", '// load("res://not_found.tscn")\n')
        self.assertEqual(self.report().findings, [])

    def test_ignores_cs_comment(self):
        self.put("Thing.cs", '// var x = load("res://missing.tscn");\n')
        self.assertEqual(self.report().findings, [])

    def test_ignore_marker_inside_literal(self):
        self.put("main.tscn", '[ext_resource path="res://foo#bar.gd" id="1"]')
        self.put("foo#bar.gd", "extends Node\n")
        self.assertEqual(self.report().findings, [])

    def test_ignore_slash_comment_inside_literal(self):
        self.put("x.cs", 'var a = load("res://main.tscn"); // comment\n')
        self.assertEqual(self.report().findings, [])

    def test_does_not_parse_dynamic_load(self):
        self.put("x.gd", 'var a = load("res://" + name)\n')
        # Dynamic paths cannot be validated statically.
        self.assertEqual(self.report().findings, [])

    def test_literal_call_in_message_not_treated_as_code(self):
        self.put("x.gd", 'print("preload(\\"res://missing.tres\\")")\n')
        self.assertEqual(self.report().findings, [])

    def test_load_with_additional_arguments(self):
        self.put("x.gd", 'var a = load("res://main.tscn", "PackedScene")\n')
        self.assertEqual(self.report().references, 2)

    def test_dynamic_suffix_not_treated_as_static_path(self):
        self.put("x.gd", 'var a = load("res://units/" + unit_id + ".tscn")')
        self.assertEqual(self.report().findings, [])

    def test_invalid_parent_traversal(self):
        self.put("main.tscn", 'path="res://../secret.tres"\n')
        self.assertIn("INVALID_URI", self.codes())

    def test_invalid_empty_path(self):
        self.put("main.tscn", 'path="res://"\n')
        self.assertIn("INVALID_URI", self.codes())

    def test_invalid_double_slash(self):
        self.put("main.tscn", 'path="res://foo//bar.tres"\n')
        self.assertIn("INVALID_URI", self.codes())

    def test_invalid_current_directory(self):
        self.put("main.tscn", 'path="res://./bar.tres"\n')
        self.assertIn("INVALID_URI", self.codes())

    def test_invalid_backslash(self):
        self.put("main.tscn", 'path="res://foo\\bar.tres"\n')
        self.assertIn("INVALID_URI", self.codes())

    def test_invalid_drive_letter(self):
        self.put("main.tscn", 'path="res://C:/bar.tres"\n')
        self.assertIn("INVALID_URI", self.codes())

    def test_case_mismatch(self):
        self.put("Assets/MyMesh.tres", "[gd_resource]\n")
        self.put("main.tscn", 'path="res://assets/mymesh.tres"\n')
        self.assertIn("CASE_MISMATCH", self.codes())
        self.assertNotIn("MISSING_RESOURCE", self.codes())

    def test_case_collision(self):
        self.put("Textures/A.png", "1")
        self.put("Textures/a.png", "2")
        self.assertEqual(self.codes().count("CASE_COLLISION"), 2)

    def test_casefold_unicode(self):
        self.put("Textures/Ä.png", "1")
        self.put("Textures/ä.png", "2")
        self.assertEqual(self.codes().count("CASE_COLLISION"), 2)

    def test_excludes_globs(self):
        self.put("unused/bad.tscn", 'path="res://missing.tres"')
        self.assertIn("MISSING_RESOURCE", self.codes())
        self.assertNotIn("MISSING_RESOURCE", self.codes(exclude=["unused/*"]))

    def test_excludes_directory(self):
        self.put("addons/vendor/bad.gd", 'var x = load("res://gone.tres")')
        self.assertNotIn("MISSING_RESOURCE", self.codes(exclude=["addons/vendor"]))

    def test_skips_editor_cache(self):
        self.put(".godot/editor/a.tscn", 'path="res://missing.tres"')
        self.assertEqual(self.report().files, 2)

    def test_skips_git_folder(self):
        self.put(".git/config", "source")
        self.assertEqual(self.report().files, 2)

    def test_includes_nontext_assets(self):
        self.put("icon.png", "not real PNG but path should exist")
        self.put("main.tscn", 'path="res://icon.png"')
        self.assertEqual(self.report().findings, [])

    def test_unicode_path(self):
        self.put("Мир/лес.tres", "[gd_resource]")
        self.put("main.tscn", 'path="res://Мир/лес.tres"')
        self.assertEqual(self.report().findings, [])

    def test_duplicate_reference_on_one_line_deduped(self):
        self.put("main.tscn", 'path="res://other.tres" path="res://other.tres"')
        self.assertEqual(self.report().references, 2)

    def test_duplicate_reference_different_lines_preserved(self):
        self.put("main.tscn", 'path="res://absent.tres"\npath="res://absent.tres"')
        self.assertEqual(self.codes().count("MISSING_RESOURCE"), 2)

    def test_line_number(self):
        self.put("main.tscn", '\n\npath="res://bad.tres"\n')
        findings = [f for f in self.report().findings if f.code == "MISSING_RESOURCE"]
        self.assertEqual(findings[0].line, 3)

    def test_utf8_bom(self):
        (self.root / "main.tscn").write_bytes(b'\xef\xbb\xbfpath="res://main.tscn"')
        self.assertEqual(self.report().findings, [])

    def test_binary_text_resource(self):
        (self.root / "main.tscn").write_bytes(b'\xff\xff')
        self.assertIn("UNREADABLE_TEXT", self.codes())

    def test_cycle_detection(self):
        self.put("a.tres", 'path="res://b.tres"')
        self.put("b.tres", 'path="res://a.tres"')
        self.assertEqual(self.codes().count("DEPENDENCY_CYCLE"), 1)

    def test_cycle_detection_disabled(self):
        self.put("a.tres", 'path="res://b.tres"')
        self.put("b.tres", 'path="res://a.tres"')
        self.assertEqual(self.codes(check_cycles=False), [])

    def test_cycle_three_nodes(self):
        self.put("a.gd", 'preload("res://b.gd")')
        self.put("b.gd", 'preload("res://c.gd")')
        self.put("c.gd", 'preload("res://a.gd")')
        self.assertEqual(self.codes().count("DEPENDENCY_CYCLE"), 1)

    def test_no_cycle_for_diamond(self):
        self.put("a.gd", 'preload("res://b.gd")\npreload("res://c.gd")')
        self.put("b.gd", 'preload("res://d.gd")')
        self.put("c.gd", 'preload("res://d.gd")')
        self.put("d.gd", "extends Node")
        self.assertNotIn("DEPENDENCY_CYCLE", self.codes())

    def test_self_reference_not_reported_as_cycle(self):
        self.put("a.gd", 'preload("res://a.gd")')
        self.assertEqual(self.codes(), [])

    def test_cycle_algorithm_long_chain_no_recursion(self):
        graph = {f"a{i}": [f"a{i + 1}"] for i in range(2500)}
        graph["a2500"] = ["a0"]
        self.assertEqual(len(audit.find_cycles(graph)), 1)
        self.assertEqual(len(audit.find_cycles(graph)[0]), 2501)

    def test_cycle_algorithm_dense_dag_has_no_false_cycles(self):
        # Previously a 350-node complete DAG could queue 61,075 redundant
        # DFS work items before reaching the oldest pending sibling.
        n = 350
        graph = {f"n{i:03d}": [f"n{j:03d}" for j in range(i + 1, n)]
                 for i in range(n)}
        self.assertEqual(audit.find_cycles(graph), [])

    def test_cycle_algorithm_dense_component_reported_once(self):
        n = 80
        nodes = [f"n{i:03d}" for i in range(n)]
        graph = {source: [target for target in nodes if target != source]
                 for source in nodes}
        self.assertEqual(audit.find_cycles(graph), [tuple(nodes)])

    def test_cycle_algorithm_matches_independent_reachability_oracle(self):
        from random import Random
        random = Random(19112026)
        for n in range(1, 13):
            nodes = [f"v{i:02d}" for i in range(n)]
            for trial in range(20):
                # Leave the last node without an explicit adjacency entry to
                # cover destination-only nodes as well as complete components.
                graph = {source: [target for target in nodes if random.random() < 0.25]
                         for source in nodes[:-1]}
                reachable = {}
                for start in nodes:
                    visited = {start}
                    pending = [start]
                    while pending:
                        for next_node in graph.get(pending.pop(), ()):
                            if next_node not in visited:
                                visited.add(next_node)
                                pending.append(next_node)
                    reachable[start] = visited
                remaining = set(nodes)
                expected = []
                while remaining:
                    start = min(remaining)
                    component = tuple(sorted(node for node in remaining
                                             if node in reachable[start]
                                             and start in reachable[node]))
                    remaining.difference_update(component)
                    if len(component) > 1:
                        expected.append(component)
                with self.subTest(n=n, trial=trial):
                    self.assertEqual(audit.find_cycles(graph), sorted(expected))

    def test_cycle_algorithm_disconnected_graph(self):
        graph = {"a": ["b"], "b": ["a"], "c": ["d"], "d": ["c"], "e": []}
        self.assertEqual(audit.find_cycles(graph), [("a", "b"), ("c", "d")])

    def test_report_json(self):
        self.put("main.tscn", 'path="res://missing.tres"')
        report = self.report().to_dict()
        data = json.loads(json.dumps(report))
        self.assertEqual(data["summary"]["errors"], 1)
        self.assertEqual(data["summary"]["warnings"], 0)
        self.assertEqual(data["findings"][0]["code"], "MISSING_RESOURCE")

    def test_sorted_deterministic(self):
        self.put("z.tres", 'path="res://z_bad.tres"')
        self.put("a.tres", 'path="res://a_bad.tres"')
        self.assertEqual(self.report().to_dict(), self.report().to_dict())
        self.assertEqual([f.path for f in self.report().findings], ["a.tres", "z.tres"])

    def test_symlink_outside_project(self):
        external = Path(self.temp.name) / "secret.tres"
        external.write_text("secret")
        try:
            (self.root / "secret.tres").symlink_to(external)
        except (OSError, NotImplementedError):
            self.skipTest("symlinks unavailable")
        self.put("main.tscn", 'path="res://secret.tres"')
        self.assertIn("OUTSIDE_PROJECT", self.codes())

    def test_symlink_to_existing_project_resource(self):
        target = self.put("assets/original.tres", "[gd_resource]")
        alias = self.root / "alias.tres"
        try:
            alias.symlink_to(target)
        except (OSError, NotImplementedError):
            self.skipTest("symlinks unavailable")
        self.put("main.tscn", 'path="res://alias.tres"')
        self.assertEqual(self.report().findings, [])

    def test_dangling_symlink_reference_is_missing(self):
        link = self.root / "dangling.tres"
        try:
            link.symlink_to(self.root / "does_not_exist.tres")
        except (OSError, NotImplementedError):
            self.skipTest("symlinks unavailable")
        self.put("main.tscn", 'path="res://dangling.tres"')
        self.assertIn("MISSING_RESOURCE", self.codes())

    def test_symlink_cycle_is_reported_not_crashed(self):
        first = self.root / "one.tres"
        second = self.root / "two.tres"
        try:
            first.symlink_to(second)
            second.symlink_to(first)
        except (OSError, NotImplementedError):
            self.skipTest("symlinks unavailable")
        self.put("main.tscn", 'path="res://one.tres"')
        self.assertIn("UNRESOLVABLE_RESOURCE", self.codes())

    def test_cli_text_success(self):
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            code = audit.main([str(self.root)])
        self.assertEqual(code, 0)
        self.assertIn("errors: 0", buf.getvalue())

    def test_cli_error_exit_code(self):
        self.put("main.tscn", 'path="res://nope.tres"')
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(audit.main([str(self.root)]), 1)
            self.assertEqual(audit.main([str(self.root), "--fail-on", "none"]), 0)

    def test_cli_warning_exit_code(self):
        self.put("a.tres", 'path="res://b.tres"')
        self.put("b.tres", 'path="res://a.tres"')
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(audit.main([str(self.root)]), 0)
            self.assertEqual(audit.main([str(self.root), "--fail-on", "warning"]), 1)

    def test_cli_github_annotations(self):
        self.put("main.tscn", 'path="res://not_found.tres"')
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = audit.main([str(self.root), "--format", "github"])
        self.assertEqual(code, 1)
        self.assertIn("::error file=main.tscn,line=1,title=MISSING_RESOURCE::", out.getvalue())

    def test_github_annotation_injection_is_escaped(self):
        report = audit.AuditReport("root", 1, 1, [audit.Finding("error", "INVALID", "some,file", 1, "line1\n::warning title=hacked::line2", "res://x")], {})
        result = audit._render_github(report)
        self.assertEqual(len(result.splitlines()), 1)
        self.assertIn("some%2Cfile", result)
        self.assertIn("%0A", result)

    def test_cli_json_output_file(self):
        output = Path(self.temp.name) / "audit.json"
        with contextlib.redirect_stdout(io.StringIO()):
            code = audit.main([str(self.root), "--format", "json", "--output", str(output)])
        self.assertEqual(code, 0)
        self.assertIn("summary", json.loads(output.read_text()))

    def test_cli_subprocess_works_from_another_cwd(self):
        script = Path(audit.__file__)
        result = subprocess.run([sys.executable, str(script), str(self.root), "--format", "json"], cwd=self.temp.name, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["summary"]["errors"], 0)

    def test_cli_invalid_root_exits_with_usage(self):
        (self.root / "project.godot").unlink()
        with contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit) as result:
                audit.main([str(self.root)])
        self.assertEqual(result.exception.code, 2)

    def test_excludes_one_file_but_keeps_directory(self):
        self.put("files/one.tscn", 'path="res://missing.tres"')
        self.put("files/two.tscn", "[gd_scene]")
        report = self.report(exclude=["files/one.tscn"])
        self.assertEqual(report.findings, [])
        self.assertIn("files/two.tscn", report.graph)

    def test_function_inside_string_does_not_count_as_reference(self):
        self.put("x.gd", 'var message = "load(\'res://missing.tres\')"\n')
        self.assertEqual(self.report().findings, [])

    def test_escaped_quote_inside_literal_does_not_end_string(self):
        line = 'print("escaped \\" still inside load(\'res://missing.tres\')")'
        self.assertFalse(audit._outside_quotes(line, line.index("load(")))

    def test_uri_requires_resource_scheme(self):
        self.assertIn("res://", audit._validate_uri("uid://test"))

    def test_cycle_algorithm_shared_sibling_node(self):
        self.assertEqual(audit.find_cycles({"a": ["b", "c"], "b": ["c"], "c": []}), [])

    def test_script_main_entrypoint(self):
        import runpy
        from unittest.mock import patch
        with patch.object(sys, "argv", [str(audit.__file__), str(self.root)]):
            with contextlib.redirect_stdout(io.StringIO()):
                with self.assertRaises(SystemExit) as result:
                    runpy.run_path(str(audit.__file__), run_name="__main__")
        self.assertEqual(result.exception.code, 0)


if __name__ == "__main__":
    unittest.main()
