"""Unit-level contracts for the display-only rendering stress harness."""
import re
from pathlib import Path
import unittest

import run_gpu


class GPUCaseTests(unittest.TestCase):
    def test_script_and_runner_registries_match(self):
        script = (Path(__file__).resolve().parent / "gpu_stress.gd").read_text(encoding="utf-8")
        match = re.search(r"const CASES := \[(.*?)\]", script, re.S)
        self.assertIsNotNone(match)
        names = re.findall(r'"([^"]+)"', match.group(1))
        self.assertEqual(names, list(run_gpu.GPU_CASES))

    def test_command_never_enables_dummy_headless(self):
        cmd = run_gpu.build_gpu_command("godot", Path("/tmp"), "multimesh_3d", 2, 30, 5, [])
        self.assertIn("res://gpu_stress.gd", cmd)
        self.assertNotIn("--headless", cmd)
        self.assertEqual(cmd[-4:], ["--case=multimesh_3d", "--scale=2", "--frames=30", "--seed=5"])

    def test_invalid_gpu_case_rejected(self):
        with self.assertRaisesRegex(ValueError, "Unknown GPU case"):
            run_gpu.build_gpu_command("godot", Path("."), "physics_2d", 1, 12, 123, [])

    def test_frame_summary_ignores_failed_runs(self):
        runs = [{"status": "passed", "engine": {"detail": {"frame_p95_ms": 12.0}}},
                {"status": "failed"}, {"status": "passed", "engine": {"detail": {"frame_p95_ms": 30.0}}}]
        self.assertEqual(run_gpu.frame_summary(runs)["median_frame_p95_ms"], 21.0)

    def test_report_contains_failure_and_frame_latency(self):
        sample = {"cases": {"cpu_particles": {"status": "failed",
                  "median_engine_ms": None, "median_frame_p95_ms": 42.0,
                  "max_rss_mib": 128.0}}, "failures": ["cpu_particles: timeout"]}
        result = run_gpu.render_table(sample)
        self.assertIn("42.000", result)
        self.assertIn("cpu_particles: timeout", result)


if __name__ == "__main__":
    unittest.main()
