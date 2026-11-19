"""Static guard against overlapping engine stress-case additions."""
from pathlib import Path
import re
import unittest

import run


class RegistryConsistencyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.script = Path(__file__).with_name("stress.gd").read_text(encoding="utf-8")

    def test_cases_match_engine_registration(self):
        match = re.search(r"const CASES := \[([\s\S]*?)\]", self.script)
        self.assertIsNotNone(match)
        declared = re.findall(r'"([a-z0-9_]+)"', match.group(1))
        self.assertEqual(list(run.CASES), declared)

    def test_no_duplicate_case_identifiers_or_dispatch_arms(self):
        declarations = re.findall(r'const CASES := \[([\s\S]*?)\]', self.script)
        declared = re.findall(r'"([a-z0-9_]+)"', declarations[0])
        dispatcher = self.script.split("func _run_case(", 1)[1].split("\n\nfunc ", 1)[0]
        dispatched = re.findall(r'^\t\t"([a-z0-9_]+)":', dispatcher, re.MULTILINE)
        self.assertEqual(len(declared), len(set(declared)))
        self.assertEqual(len(dispatched), len(set(dispatched)))
        self.assertEqual(set(declared), set(dispatched))

    def test_no_duplicate_gdscript_functions(self):
        functions = re.findall(r"^func ([a-zA-Z0-9_]+)\(", self.script, re.MULTILINE)
        self.assertEqual(len(functions), len(set(functions)))

    def test_new_graph_and_animation_cases_exist(self):
        self.assertIn("astar_graph", run.CASES)
        self.assertIn("animation_tracks", run.CASES)


if __name__ == "__main__":
    unittest.main()
