"""Regression checks for the added engine load scenarios."""
import unittest
from pathlib import Path

import run


ADDED = (
    "packed_arrays", "sorting", "animation_tracks",
    "physics_raycast_2d", "physics_raycast_3d", "render_multimesh_3d",
    "curve_bake", "curve_nearest",
)


class WorkloadExtensionsTests(unittest.TestCase):
    def test_each_workload_is_registered_and_dispatched(self):
        script = (Path(__file__).parent / "stress.gd").read_text(encoding="utf-8")
        for name in ADDED:
            with self.subTest(name=name):
                self.assertIn(name, run.CASES)
                self.assertIn('"'+name+'"', script)
                self.assertIn('func _'+name+'(', script)

    def test_multimesh_cannot_run_on_dummy_headless_renderer(self):
        self.assertIn("render_multimesh_3d", run.RENDER_CASES)
        self.assertNotIn("render_multimesh_3d", run.choose_cases([], "headless"))
        with self.assertRaisesRegex(ValueError, "requires --render-mode display"):
            run.choose_cases(["render_multimesh_3d"], "headless")


if __name__ == "__main__":
    unittest.main()
