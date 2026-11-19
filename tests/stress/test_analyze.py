"""Regression tests for stress bottleneck triage."""
import csv
import io
import unittest

import analyze


def report(name="math", *, engine=100., wall=1., rss=100., frame=None, status="passed"):
    detail = {} if frame is None else {"frame_interval_ms": {"p95": frame}}
    return {"schema_version": 1, "configuration": {
        "preset": "smoke", "scale": 1, "frames": 12, "render_mode": "headless", "seed": 42},
        "cases": {name: {"status": status, "median_wall_seconds": wall,
                          "median_cpu_seconds": .2, "max_rss_mib": rss,
                          "median_engine_ms": engine, "runs": [{"status": status,
                          "engine": {"duration_ms": engine, "detail": detail}}]}}}


class AnalyzerTests(unittest.TestCase):
    def test_absence_of_baseline_does_not_invent_regression(self):
        row = analyze.analyze(report())[0]
        self.assertIsNone(row["engine_delta_pct"])
        self.assertEqual(row["priority"], 0)

    def test_engine_regression_even_if_wall_unchanged(self):
        now, old = report(engine=140.), report(engine=100.)
        self.assertIn("engine time regression +40.0%", analyze.analyze(now, old)[0]["findings"])

    def test_mismatched_seed_rejected(self):
        now, old = report(), report()
        old["configuration"]["seed"] = 7
        with self.assertRaisesRegex(ValueError, "seed"):
            analyze.analyze(now, old)

    def test_failed_scenario_first(self):
        now = report("slow", frame=50)
        now["cases"].update(report("broken", status="failed")["cases"])
        self.assertEqual(analyze.analyze(now)[0]["case"], "broken")

    def test_frame_and_memory_thresholds(self):
        row = analyze.analyze(report(frame=42., rss=3000.))[0]
        self.assertEqual(row["priority"], 60)
        self.assertIn("RSS", row["findings"])

    def test_worst_per_run_p95(self):
        now = report(frame=22.)
        now["cases"]["math"]["runs"].append({"status": "passed",
            "engine": {"detail": {"frame_interval_ms": {"p95": 55.}}}})
        self.assertEqual(analyze.analyze(now)[0]["frame_p95_ms"], 55.)

    def test_nonfinite_samples_are_ignored(self):
        now = report(frame=float("nan"), engine=float("inf"))
        row = analyze.analyze(now)[0]
        self.assertIsNone(row["frame_p95_ms"])
        self.assertIsNone(row["engine_ms"])

    def test_csv_and_markdown_escaping(self):
        rows = analyze.analyze(report())
        rows[0]["findings"] = "a|b"
        self.assertIn("a\\|b", analyze.as_markdown(rows, False))
        parsed = list(csv.DictReader(io.StringIO(analyze.as_csv(rows))))
        self.assertEqual(parsed[0]["findings"], "a|b")


if __name__ == "__main__":
    unittest.main()
