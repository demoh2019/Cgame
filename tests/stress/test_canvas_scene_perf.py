"""Registration and workload invariants for CanvasItem/SceneTree CPU probes."""
from pathlib import Path
import unittest

import run


ROOT = Path(__file__).parent
SCRIPT = (ROOT / "stress.gd").read_text(encoding="utf-8")
HELPER = (ROOT / "canvas_scene_perf.gd").read_text(encoding="utf-8")


class CanvasScenePerformanceTests(unittest.TestCase):
    def test_scenarios_registered_and_callable_headless(self):
        for name in ("canvas_transform_2d", "process_dispatch"):
            with self.subTest(name=name):
                self.assertIn(name, run.CASES)
                self.assertNotIn(name, run.RENDER_CASES)
                self.assertIn('"' + name + '":', SCRIPT)
                self.assertEqual(run.choose_cases([name], "headless"), [name])

    def test_cpu_probes_have_deterministic_checksums_and_bounds(self):
        self.assertIn("func canvas_transform(", HELPER)
        self.assertIn("func process_dispatch(", HELPER)
        self.assertIn("mini(128 * scale, 4096)", HELPER)
        self.assertIn("mini(300 * scale, 6000)", HELPER)
        self.assertIn("transform_mutation_ms", HELPER)
        self.assertIn("global_transform_rebuild_ms", HELPER)
        self.assertIn("avg_process_ms", HELPER)
        self.assertIn("peak_physics_ms", HELPER)
        self.assertIn('"checksum"', HELPER)


if __name__ == "__main__":
    unittest.main()
