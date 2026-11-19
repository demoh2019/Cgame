"""Comparison safety, ranking and output tests for stress analyzer."""
import unittest

import analyze_hotspots as a


def report(engine=100.0, frame=12.0, rss=100.0, repeats=3):
    runs = [{"status": "passed", "engine": {
        "duration_ms": engine, "detail": {"frame_p95_ms": frame}}}
        for _ in range(repeats)]
    return {"status": "passed",
            "host": {"platform": "linux", "logical_cpus": 8},
            "configuration": {"preset": "standard", "scale": 4,
                              "frames": 90, "render_mode": "display"},
            "failures": [],
            "cases": {"shader_variants": {
                "status": "passed", "runs": runs,
                "median_engine_ms": engine,
                "median_wall_seconds": 1.0,
                "median_cpu_seconds": 0.5,
                "max_rss_mib": rss,
                "median_frame_p95_ms": frame}}}


class HotspotAnalyzerTests(unittest.TestCase):
    def test_engine_and_frame_regression_ranking(self):
        old = report()
        new = report(engine=150, frame=24, rss=110)
        rows = a.analyze(new, old)["regressions"]
        self.assertEqual(rows[0]["metric"], "median_frame_p95_ms")
        self.assertEqual(rows[0]["increase_pct"], 100.0)
        self.assertEqual(rows[0]["sample_repeats"], 3)
        self.assertFalse(rows[0]["low_confidence"])
        self.assertEqual({r["metric"] for r in rows},
                         {"median_frame_p95_ms", "median_engine_ms", "max_rss_mib"})

    def test_reference_must_match_scale_mode_and_host(self):
        old = report()
        new = report()
        new["configuration"]["scale"] = 50
        with self.assertRaisesRegex(ValueError, "scale"):
            a.analyze(new, old)
        new = report()
        new["host"]["logical_cpus"] = 16
        with self.assertRaisesRegex(ValueError, "logical_cpus"):
            a.analyze(new, old)

    def test_missing_optional_metrics_are_ignored(self):
        new, old = report(), report()
        new["cases"]["shader_variants"].pop("median_frame_p95_ms")
        old["cases"]["shader_variants"].pop("median_frame_p95_ms")
        self.assertEqual(a.case_metrics(new["cases"]["shader_variants"])["median_frame_p95_ms"], 12.0)
        self.assertEqual(a.analyze(new, old)["regressions"], [])

    def test_low_sample_confidence_flag(self):
        rows = a.analyze(report(engine=200, repeats=1), report(repeats=1))["regressions"]
        self.assertTrue(rows[0]["low_confidence"])
        self.assertEqual(rows[0]["sample_repeats"], 1)

    def test_failed_case_skipped(self):
        new = report()
        new["cases"]["shader_variants"]["status"] = "failed"
        result = a.analyze(new, report())
        self.assertEqual(result["regressions"], [])
        self.assertIn("scenario not passed", result["failures"][0])

    def test_memory_growth_is_heuristic_not_diagnosis(self):
        new = report()
        new["cases"]["memory_churn"] = {
            "status": "passed",
            "runs": [{"status": "passed", "engine": {
                "detail": {"retained_growth_bytes": 128 * 1048576}}}],
        }
        result = a.analyze(new, leak_warning_mib=64)
        self.assertEqual(len(result["memory_signals"]), 1)
        self.assertIn("NOT proof", result["memory_signals"][0]["note"])

    def test_markdown_and_csv_explain_findings(self):
        result = a.analyze(report(engine=150), report())
        md = a.markdown(result)
        csv = a.csv_text(result)
        self.assertIn("shader_variants", md)
        self.assertIn("same model", md)
        self.assertIn("increase_pct", csv)
        self.assertIn("50.0", csv)

    def test_negative_or_non_finite_metrics_dropped(self):
        self.assertIsNone(a.numeric(float("nan")))
        self.assertIsNone(a.numeric(float("inf")))
        self.assertIsNone(a.numeric(True))
        self.assertEqual(a.numeric(1), 1.0)


if __name__ == "__main__":
    unittest.main()
