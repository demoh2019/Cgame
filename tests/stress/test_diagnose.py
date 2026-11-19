"""Independent tests for markdown hotspot analysis and stress-case coverage."""
from pathlib import Path
import unittest

import diagnose
import run as stress


def case(engine_ms: float, wall: float, rss: float, spike: float = 0.0):
    return {
        "status": "passed", "median_engine_ms": engine_ms,
        "median_wall_seconds": wall, "max_rss_mib": rss,
        "runs": [{"status": "passed", "engine": {"detail": {"peak_frame_ms": spike}}}],
    }


class DiagnosisTests(unittest.TestCase):
    def report(self):
        return {"status": "passed", "configuration": {
            "preset": "smoke", "scale": 1, "frames": 12, "render_mode": "headless", "seed": 42,
        }, "cases": {"fast": case(3., 1., 40., 2.),
                      "slow": case(5., 4., 100., 20.)}, "failures": []}

    def test_rankings_and_spikes(self):
        result = diagnose.build_report(self.report(), top=1)
        self.assertIn("slow | 5.000", result)
        self.assertIn("slow | 100.000", result)
        self.assertIn("slow | 20.000", result)
        self.assertNotIn("fast | 3.000", result)

    def test_baseline_regressions(self):
        baseline = self.report()
        current = self.report()
        current["cases"]["slow"]["median_engine_ms"] = 10.
        result = diagnose.build_report(current, baseline)
        self.assertIn("slow | engine ms | 5.000 | 10.000 | +100.0%", result)

    def test_mismatched_baseline_rejected(self):
        baseline = self.report()
        baseline["configuration"]["seed"] = 999
        with self.assertRaisesRegex(ValueError, "seed"):
            diagnose.build_report(self.report(), baseline)

    def test_missing_metrics_and_failed_runs(self):
        report = self.report()
        report["cases"] = {"broken": {"status": "failed", "runs": [
            {"status": "failed", "engine": {"detail": {"peak_frame_ms": 200.}}}]}}
        report["failures"] = ["broken #1: crash"]
        output = diagnose.build_report(report)
        self.assertIn("broken #1: crash", output)
        self.assertIn("No frame-timing measurements available", output)

    def test_reject_non_finite(self):
        self.assertIsNone(diagnose.finite(float("nan")))
        self.assertIsNone(diagnose.finite(True))
        self.assertIsNone(diagnose.delta_percent(10., 0.))

    def test_manifest_matches_script(self):
        script = (Path(__file__).parent / "stress.gd").read_text(encoding="utf-8")
        for name in stress.CASES:
            self.assertIn('"' + name + '"', script)
        for name in ("compression", "regex", "astar_3d", "resource_load",
                     "input_map", "transform_hierarchy"):
            self.assertIn('\t\t"' + name + '":', script)

    def test_engine_duration_summary(self):
        runs = [
            {"status": "passed", "wall_seconds": 1., "peak_rss_mib": 50.,
             "engine": {"duration_ms": 100., "engine_memory_after_bytes": 1000}},
            {"status": "passed", "wall_seconds": 2., "peak_rss_mib": 60.,
             "engine": {"duration_ms": 150., "engine_memory_after_bytes": 1200}},
        ]
        summary = stress.summarize(runs)
        self.assertEqual(summary["median_engine_ms"], 125.)
        self.assertEqual(summary["p95_engine_ms"], 150.)
        self.assertEqual(summary["max_engine_memory_bytes"], 1200)


if __name__ == "__main__":
    unittest.main()
