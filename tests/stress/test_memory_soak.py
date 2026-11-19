"""Unit tests for in-process long-lived Cgame memory soak diagnostics."""
from pathlib import Path
import unittest
from unittest.mock import patch

import memory_soak as soak


def fake_result(samples, scenario="nodes", cycles=None, batch=10):
    return {"status": "passed", "engine": {"detail": {
        "scenario": scenario, "cycles": len(samples) if cycles is None else cycles,
        "batch": batch, "engine_static_memory_bytes": samples,
    }}}


class MemoryAnalysisTests(unittest.TestCase):
    def test_flat_memory_has_no_retained_growth(self):
        report = soak.analyze_samples([100 * 1048576] * 30)
        self.assertEqual(report["retained_growth_mib"], 0)
        self.assertEqual(report["trend_mib_per_cycle"], 0)

    def test_linear_growth_is_detected(self):
        samples = [(100 + i) * 1048576 for i in range(30)]
        report = soak.analyze_samples(samples)
        self.assertGreater(report["retained_growth_mib"], 15)
        self.assertAlmostEqual(report["trend_mib_per_cycle"], 1.0)
        self.assertEqual(report["peak_engine_static_mib"], 129.0)

    def test_warmup_is_not_treated_as_leak(self):
        samples = [100 * 1048576] + [140 * 1048576] * 29
        report = soak.analyze_samples(samples)
        self.assertEqual(report["retained_growth_mib"], 0.0)

    def test_invalid_samples_are_rejected(self):
        for samples in ([], [1, 2, 3], [1, 2, 3, -1], [1, 2, 3, float("nan")]):
            with self.subTest(samples=samples), self.assertRaises(ValueError):
                soak.analyze_samples(samples)


class MemorySoakRunnerTests(unittest.TestCase):
    def test_command_uses_isolated_script_and_scene_options(self):
        cmd = soak.build_command("godot", Path("/tmp/project"), "nodes", 15, 20, 42)
        self.assertIn("--headless", cmd)
        self.assertIn("res://memory_soak.gd", cmd)
        self.assertEqual(cmd[cmd.index("--") + 1:], [
            "--case=memory_soak", "--scenario=nodes", "--scale=15",
            "--frames=20", "--seed=42",
        ])

    def test_unknown_scenario_is_rejected(self):
        with self.assertRaises(ValueError):
            soak.build_command("godot", Path("."), "unknown", 10, 20, 42)

    def test_growth_over_budget_fails(self):
        samples = [(100 + i) * 1048576 for i in range(30)]
        with patch.object(soak.stress, "run_once", return_value=fake_result(samples)):
            result = soak.run_scenario("godot", Path("."), "nodes", 10, 30, 42, 5, 1024, 2)
        self.assertEqual(result["failure"], "retained_memory_growth_exceeded")
        self.assertGreater(result["memory_analysis"]["retained_growth_mib"], 2.0)

    def test_flat_growth_passes(self):
        with patch.object(soak.stress, "run_once",
                          return_value=fake_result([100 * 1048576] * 30)):
            result = soak.run_scenario("godot", Path("."), "nodes", 10, 30, 42, 5, 1024, 2)
        self.assertEqual(result["status"], "passed")

    def test_invalid_engine_samples_fail(self):
        with patch.object(soak.stress, "run_once",
                          return_value=fake_result([0, 0, 0], cycles=30)):
            result = soak.run_scenario("godot", Path("."), "nodes", 10, 30, 42, 5, 1024, 2)
        self.assertEqual(result["status"], "failed")
        self.assertIn("invalid_memory_samples", result["failure"])

    def test_process_failure_propagates(self):
        with patch.object(soak.stress, "run_once",
                          return_value={"status": "failed", "failure": "rss_limit_exceeded"}):
            result = soak.run_scenario("godot", Path("."), "packed", 10, 30, 42, 5, 1024, 2)
        self.assertEqual(result["failure"], "rss_limit_exceeded")


if __name__ == "__main__":
    unittest.main()
