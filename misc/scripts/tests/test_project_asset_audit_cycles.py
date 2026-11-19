#!/usr/bin/env python3
"""Regression tests for deterministic static Godot resource dependency graphs."""

from __future__ import annotations

from contextlib import redirect_stdout
from io import StringIO
import json
from pathlib import Path
import random
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import project_asset_audit as audit  # noqa: E402


class CycleAlgorithmTests(unittest.TestCase):
    def test_empty_graph(self):
        self.assertEqual(audit.find_dependency_cycles({}), [])

    def test_simple_acyclic_chain(self):
        self.assertEqual(audit.find_dependency_cycles({"a": {"b"}, "b": {"c"}}), [])

    def test_self_reference_is_a_cycle(self):
        self.assertEqual(audit.find_dependency_cycles({"a": {"a"}}), [("a",)])

    def test_two_node_cycle(self):
        self.assertEqual(audit.find_dependency_cycles({"b": {"a"}, "a": {"b"}}),
                         [("a", "b")])

    def test_multiple_components(self):
        graph = {"d": {"c"}, "b": {"a", "c"}, "a": {"b"}, "c": {"d"}}
        self.assertEqual(audit.find_dependency_cycles(graph),
                         [("a", "b"), ("c", "d")])

    def test_cycle_with_outgoing_acyclic_edge(self):
        graph = {"a": {"b"}, "b": {"a", "c"}, "c": {"d"}}
        self.assertEqual(audit.find_dependency_cycles(graph), [("a", "b")])

    def test_incoming_edge_not_in_cycle(self):
        graph = {"x": {"a"}, "a": {"b"}, "b": {"a"}}
        self.assertEqual(audit.find_dependency_cycles(graph), [("a", "b")])

    def test_deterministic_regardless_of_insertion_order(self):
        graph = {"x": {"z", "y"}, "z": {"x"}, "y": {"x"}, "s": {"s"}}
        backwards = dict(reversed(list(graph.items())))
        self.assertEqual(audit.find_dependency_cycles(graph),
                         audit.find_dependency_cycles(backwards))

    def test_very_long_chain_does_not_recurse(self):
        graph = {str(i): {str(i + 1)} for i in range(5000)}
        self.assertEqual(audit.find_dependency_cycles(graph), [])
        graph["5000"] = {"4999"}
        self.assertEqual(audit.find_dependency_cycles(graph), [("4999", "5000")])

    def test_brute_force_small_random_graphs(self):
        rng = random.Random(731)
        for _ in range(80):
            nodes = [str(i) for i in range(rng.randint(1, 7))]
            graph = {s: {t for t in nodes if rng.random() < .3} for s in nodes}

            def reachable(source, target):
                visited = set()
                todo = [source]
                while todo:
                    node = todo.pop()
                    if node == target:
                        return True
                    if node in visited:
                        continue
                    visited.add(node)
                    todo.extend(graph[node])
                return False

            expected = []
            for source in nodes:
                if any(source in component for component in expected):
                    continue
                component = tuple(sorted(node for node in nodes
                                         if reachable(source, node)
                                         and reachable(node, source)))
                if len(component) > 1 or (len(component) == 1
                                         and source in graph[source]):
                    expected.append(component)
            self.assertEqual(audit.find_dependency_cycles(graph), sorted(expected))


class ProjectCycleTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    def write(self, relative, text=""):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        return path

    def scan(self, **kwargs):
        return audit.scan_project(self.root, **kwargs)

    def cycle_findings(self, **kwargs):
        return [f for f in self.scan(**kwargs).findings
                if f.code == "DEPENDENCY_CYCLE"]

    def test_two_scripts_cycle_warning(self):
        self.write("a.gd", 'preload("res://b.gd")')
        self.write("b.gd", 'preload("res://a.gd")')
        report = self.scan()
        self.assertEqual(report.errors, 0)
        self.assertEqual(report.warnings, 1)
        self.assertEqual(report.dependencies, {"a.gd": ["b.gd"], "b.gd": ["a.gd"]})
        self.assertEqual(self.cycle_findings()[0].source, "a.gd")

    def test_self_reference_warning(self):
        self.write("a.gd", 'load("res://a.gd")')
        self.assertEqual(len(self.cycle_findings()), 1)

    def test_acyclic_dependencies_are_exported_to_json(self):
        self.write("a.gd", 'preload("res://b.gd")')
        self.write("b.gd")
        report = self.scan()
        self.assertEqual(report.dependencies, {"a.gd": ["b.gd"]})
        self.assertEqual(report.to_dict()["dependencies"], {"a.gd": ["b.gd"]})
        self.assertEqual(self.cycle_findings(), [])

    def test_scene_script_cycle(self):
        self.write("scene.tscn", 'path="res://logic.gd"')
        self.write("logic.gd", 'const SCENE = preload("res://scene.tscn")')
        self.assertEqual(len(self.cycle_findings()), 1)

    def test_three_node_cycle(self):
        self.write("a.tres", 'path="res://b.tres"')
        self.write("b.tres", 'path="res://c.tres"')
        self.write("c.tres", 'path="res://a.tres"')
        self.assertIn("c.tres", self.cycle_findings()[0].message)

    def test_independent_cycles_produce_two_findings(self):
        for name, other in (("a", "b"), ("b", "a"), ("c", "d"), ("d", "c")):
            self.write(name + ".gd", 'preload("res://' + other + '.gd")')
        self.assertEqual([f.source for f in self.cycle_findings()],
                         ["a.gd", "c.gd"])

    def test_repeated_dependencies_deduplicated(self):
        self.write("a.gd", 'load("res://b.gd")\nload("res://b.gd")')
        self.write("b.gd", 'preload("res://a.gd")')
        self.assertEqual(self.scan().dependencies["a.gd"], ["b.gd"])

    def test_missing_resource_not_added_to_graph(self):
        self.write("a.gd", 'load("res://absent.gd")')
        report = self.scan()
        self.assertEqual(report.dependencies, {})
        self.assertEqual([f.code for f in report.findings], ["MISSING_RESOURCE"])

    def test_binary_resource_not_a_graph_node(self):
        self.write("scene.tscn", 'path="res://icon.png"')
        self.write("icon.png", "bytes")
        self.assertEqual(self.scan().dependencies, {})

    def test_comment_not_in_dependency_graph(self):
        self.write("a.gd", '# preload("res://b.gd")')
        self.write("b.gd", 'preload("res://a.gd")')
        self.assertEqual(self.cycle_findings(), [])
        self.assertEqual(self.scan().dependencies, {"b.gd": ["a.gd"]})

    def test_no_cycles_option_keeps_dependency_graph(self):
        self.write("a.gd", 'preload("res://a.gd")')
        report = self.scan(check_cycles=False)
        self.assertEqual(report.dependencies, {"a.gd": ["a.gd"]})
        self.assertEqual([f.code for f in report.findings], [])

    def test_cli_default_cycle_is_warning_only(self):
        self.write("a.gd", 'load("res://a.gd")')
        with redirect_stdout(StringIO()) as out:
            result = audit.main([str(self.root)])
        self.assertEqual(result, 0)
        self.assertIn("DEPENDENCY_CYCLE", out.getvalue())

    def test_cli_warning_as_failure(self):
        self.write("a.gd", 'load("res://a.gd")')
        with redirect_stdout(StringIO()):
            result = audit.main([str(self.root), "--fail-on-warning"])
        self.assertEqual(result, 1)

    def test_cli_no_cycles_suppresses_warning(self):
        self.write("a.gd", 'load("res://a.gd")')
        with redirect_stdout(StringIO()) as out:
            result = audit.main([str(self.root), "--no-cycles", "--fail-on-warning"])
        self.assertEqual(result, 0)
        self.assertNotIn("DEPENDENCY_CYCLE", out.getvalue())

    def test_cli_json_dependencies_stable(self):
        self.write("b.gd", 'load("res://a.gd")')
        self.write("a.gd")
        with redirect_stdout(StringIO()) as output:
            result = audit.main([str(self.root), "--format", "json"])
        self.assertEqual(result, 0)
        payload = json.loads(output.getvalue())
        self.assertEqual(payload["dependencies"], {"b.gd": ["a.gd"]})

    def test_excluded_target_does_not_form_graph_edge(self):
        self.write("vendor/a.gd", 'load("res://main.gd")')
        self.write("main.gd", 'load("res://vendor/a.gd")')
        report = self.scan(exclude=("vendor/*",))
        self.assertEqual(report.dependencies, {})
        self.assertEqual([f.code for f in report.findings if f.code == "DEPENDENCY_CYCLE"], [])

    def test_cycle_warning_is_deterministic(self):
        self.write("z.gd", 'load("res://a.gd")')
        self.write("a.gd", 'load("res://z.gd")')
        self.assertEqual(self.scan().to_dict(), self.scan().to_dict())

    def test_cycles_do_not_change_reference_count(self):
        self.write("a.gd", 'load("res://b.gd")\nload("res://b.gd")')
        self.write("b.gd", 'load("res://a.gd")')
        self.assertEqual(self.scan().references_checked, 3)

    def test_large_cycle_warning_uses_bounded_preview(self):
        for i in range(12):
            self.write(f"{i:02d}.gd", 'load("res://' + f"{(i+1)%12:02d}.gd" + '")')
        findings = self.cycle_findings()
        self.assertEqual(len(findings), 1)
        self.assertIn("12 files total", findings[0].message)


if __name__ == "__main__":
    unittest.main()
