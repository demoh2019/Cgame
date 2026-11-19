"""Keep the GDScript engine workloads and Python watchdog in lockstep.

This catches bad concurrent merges *before* a costly Cgame native build.
"""
from pathlib import Path
import re
import unittest

import run as stress

HERE = Path(__file__).resolve().parent
ENGINE_SCRIPT = HERE / "stress.gd"
EXTRA_SCRIPT = HERE / "extra_stress.gd"


def registered_cases(source: str) -> list[str]:
    match = re.search(r"(?ms)^const CASES := \[(.*?)^\]", source)
    if not match:
        raise ValueError("Godot stress.gd has no CASES list")
    return re.findall(r'"([a-z0-9_]+)"', match.group(1))


def dispatched_cases(source: str) -> list[str]:
    start = source.index("func _run_case(")
    end = source.index("func _on_sample(", start)
    result = []
    for line in source[start:end].splitlines():
        match = re.fullmatch(r'\t\t((?:"[a-z0-9_]+"(?:, )?)+):', line)
        if match:
            result.extend(re.findall(r'"([a-z0-9_]+)"', match.group(1)))
    return result


def duplicate_values(values: list[str]) -> set[str]:
    return {name for name in values if values.count(name) > 1}


class WorkloadConsistencyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.engine = ENGINE_SCRIPT.read_text(encoding="utf-8")

    def test_unique_gdscript_case_ids(self):
        names = registered_cases(self.engine)
        self.assertEqual(duplicate_values(names), set())
        self.assertGreaterEqual(len(names), 20)

    def test_python_and_gdscript_match_exactly(self):
        names = registered_cases(self.engine)
        self.assertEqual(set(names), set(stress.CASES))
        self.assertEqual(len(names), len(stress.CASES))

    def test_all_registered_cases_have_a_dispatch_target(self):
        registered = set(registered_cases(self.engine))
        actual = dispatched_cases(self.engine)
        self.assertEqual(set(actual), registered)
        self.assertEqual(duplicate_values(actual), set())

    def test_unique_gdscript_function_names(self):
        functions = re.findall(r"(?m)^func ([A-Za-z0-9_]+)\(", self.engine)
        self.assertEqual(duplicate_values(functions), set())

    def test_rendering_cases_explicitly_require_real_display(self):
        render_cases = {c for c in stress.CASES if c.startswith("render_")}
        self.assertEqual(render_cases, stress.RENDER_CASES)
        for name in render_cases:
            self.assertNotIn(name, stress.choose_cases([], "headless"))
        self.assertEqual(stress.choose_cases([], "display"), list(stress.CASES))

    def test_extra_script_exists_and_is_loaded(self):
        self.assertTrue(EXTRA_SCRIPT.is_file())
        self.assertIn('preload("res://extra_stress.gd")', self.engine)
        self.assertIn("func run(", EXTRA_SCRIPT.read_text(encoding="utf-8"))

    def test_project_entrypoint_is_available(self):
        self.assertTrue((HERE / "project.godot").is_file())
        self.assertTrue((HERE / "editor_import.py").is_file())


if __name__ == "__main__":
    unittest.main()
