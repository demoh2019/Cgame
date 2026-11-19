"""Regression tests for multi-scale workload analysis."""
import argparse
import unittest

import sweep


def report(scale, engine_ms, wall_s, rss_mib=120.0, case="containers", status="passed"):
    return {
        "configuration": {"scale": scale, "render_mode": "headless", "frames": 12,
                          "seed": 12345, "repeats": 3},
        "cases": {case: {"status": status, "median_wall_seconds": wall_s,
                         "max_rss_mib": rss_mib,
                         "runs": [{"status": status, "engine": {"duration_ms": engine_ms}}]}},
    }


class ScaleParsing(unittest.TestCase):
    def test_sorts_load_points(self):
        self.assertEqual(sweep.parse_scales("4, 1,2"), [1, 2, 4])

    def test_rejects_duplicates_nonpositive_and_singleton(self):
        for value in ("1", "2,2", "0,1", "1001,2", "1,x"):
            with self.subTest(value=value), self.assertRaises(argparse.ArgumentTypeError):
                sweep.parse_scales(value)


class RankingTests(unittest.TestCase):
    def test_flags_superlinear_growth_and_rss_delta(self):
        result = sweep.summarize_scaling([report(1, 100., 1., 200.),
                                          report(2, 300., 2., 250.),
                                          report(4, 1000., 6., 330.)], 30.)
        case = result["cases"][0]
        self.assertAlmostEqual(case["median_engine_ms_growth_excess_pct"], 150.)
        self.assertAlmostEqual(case["rss_delta_mib"], 130.)
        self.assertEqual(case["warning"], "engine time grew superlinearly")

    def test_linear_or_sublinear_is_not_warning(self):
        result = sweep.summarize_scaling([report(1, 100., 1.), report(4, 350., 2.5)], 30.)
        self.assertNotIn("warning", result["cases"][0])
        self.assertEqual(result["cases"][0]["median_engine_ms_growth_excess_pct"], -12.5)

    def test_reports_failed_scale_without_false_perf_claim(self):
        result = sweep.summarize_scaling([report(1, 100., 1.),
                                          report(4, 100., 1., status="failed")], 30.)
        self.assertEqual(result["cases"][0]["status"], "failed")
        self.assertEqual(len(result["failures"]), 1)

    def test_mismatched_settings_rejected(self):
        first, second = report(1, 10., 1.), report(4, 20., 2.)
        second["configuration"]["frames"] = 24
        with self.assertRaisesRegex(ValueError, "inconsistent configuration"):
            sweep.summarize_scaling([first, second], 30.)

    def test_nonmonotonic_scale_rejected(self):
        with self.assertRaisesRegex(ValueError, "strictly increasing"):
            sweep.summarize_scaling([report(4, 10., 1.), report(1, 20., 2.)], 30.)

    def test_missing_time_does_not_crash(self):
        first, last = report(1, 10., 1.), report(4, 40., 2.)
        first["cases"]["containers"]["runs"] = []
        result = sweep.summarize_scaling([first, last], 30.)
        self.assertIsNone(result["cases"][0]["median_engine_ms_growth_excess_pct"])


if __name__ == "__main__":
    unittest.main()
