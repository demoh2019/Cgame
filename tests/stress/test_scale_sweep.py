"""Unit tests for multi-scale stress diagnostics; no Godot executable required."""
import unittest

import scale_sweep as sweep


def point(scale, engine_ms, rss_mib=128.0, p95_ms=None):
    return {
        "scale": scale, "status": "passed",
        "median_engine_ms": engine_ms,
        "p95_engine_ms": engine_ms if p95_ms is None else p95_ms,
        "median_rss_mib": rss_mib,
    }


class ScaleValidationTests(unittest.TestCase):
    def test_valid_scales(self):
        self.assertEqual(sweep.parse_scales("1, 2, 4, 8"), [1, 2, 4, 8])

    def test_invalid_scales(self):
        for invalid in ("", "1", "1,1", "4,2", "0,2", "1,1001", "3,wat", "1,,3"):
            with self.subTest(invalid=invalid), self.assertRaises(Exception):
                sweep.parse_scales(invalid)


class ComplexityTests(unittest.TestCase):
    def test_linear_growth_not_flagged(self):
        analysis = sweep.analyze_scaling([point(1, 20), point(2, 40), point(4, 80)])
        self.assertEqual(analysis["status"], "ok")
        self.assertAlmostEqual(analysis["engine_time_exponent"], 1.0)
        self.assertEqual(analysis["engine_time_growth_factor"], 4.0)

    def test_quadratic_growth_flagged(self):
        analysis = sweep.analyze_scaling([point(1, 20), point(2, 80), point(4, 320)])
        self.assertEqual(analysis["status"], "investigate")
        self.assertAlmostEqual(analysis["engine_time_exponent"], 2.0)
        self.assertIn("possible nonlinear time growth", analysis["signals"])

    def test_noisy_result_is_distinguished(self):
        analysis = sweep.analyze_scaling([point(1, 20, p95_ms=40), point(4, 320)])
        self.assertIn("high timing variance", analysis["signals"])
        self.assertIn("possible nonlinear time growth (noisy)", analysis["signals"])

    def test_accelerating_rss(self):
        analysis = sweep.analyze_scaling([
            point(1, 20, 100), point(2, 40, 120),
            point(4, 80, 180), point(8, 160, 420),
        ])
        self.assertIn("accelerating RSS growth (investigate allocations)", analysis["signals"])
        self.assertEqual(analysis["rss_growth_mib"], 320)

    def test_failed_run_does_not_claim_complexity(self):
        bad = point(4, None)
        bad["status"] = "failed"
        analysis = sweep.analyze_scaling([point(1, 20), bad])
        self.assertEqual(analysis["status"], "failed")
        self.assertIsNone(analysis.get("engine_time_exponent"))

    def test_small_runtime_is_not_false_alarm(self):
        analysis = sweep.analyze_scaling([point(1, 0.1), point(4, 1.6)])
        self.assertEqual(analysis["status"], "ok")

    def test_unordered_scales_rejected(self):
        with self.assertRaises(ValueError):
            sweep.analyze_scaling([point(4, 40), point(1, 10)])

    def test_summary_and_rank(self):
        data = [
            {"status": "passed", "wall_seconds": 2.0, "peak_rss_mib": 110.0,
             "cpu_seconds": 1.0, "engine": {"duration_ms": 20.0}},
            {"status": "passed", "wall_seconds": 3.0, "peak_rss_mib": 120.0,
             "cpu_seconds": 1.5, "engine": {"duration_ms": 30.0}},
        ]
        stat = sweep.summarize_scale(data, 2)
        self.assertEqual(stat["median_engine_ms"], 25.0)
        self.assertEqual(stat["median_rss_mib"], 115.0)
        report = {
            "configuration": {"scales": [1, 2], "frames": 30, "repeats": 2, "render_mode": "headless"},
            "failures": [],
            "cases": {
                "linear": {"analysis": {"engine_time_exponent": 1., "rss_growth_mib": 2., "signals": []}},
                "slow": {"analysis": {"engine_time_exponent": 2., "rss_growth_mib": 60.,
                                       "signals": ["possible nonlinear time growth"]}},
            },
        }
        markdown = sweep.markdown_report(report)
        self.assertLess(markdown.index("| slow |"), markdown.index("| linear |"))


if __name__ == "__main__":
    unittest.main()
