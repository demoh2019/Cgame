"""Unit tests for multi-scale bottleneck analysis (no engine binary needed)."""
import math
import unittest

import scaling


def report(scale, duration, rss=100.0, name="script_vm", status="passed"):
    return {
        "configuration": {"scale": scale},
        "cases": {name: {
            "status": status,
            "median_engine_ms": duration,
            "max_rss_mib": rss,
        }},
    }


class ScaleParsingTests(unittest.TestCase):
    def test_valid_sorted_scale_list(self):
        self.assertEqual(scaling.parse_scales("1, 2,4,16"), [1, 2, 4, 16])

    def test_bad_or_unbounded_scales_rejected(self):
        for raw in ("4", "4,2", "2,2", "0,1", "1,1001", "no,2",
                    "1,2,3,4,5,6,7,8,9"):
            with self.subTest(raw=raw):
                with self.assertRaises(ValueError):
                    scaling.parse_scales(raw)


class GrowthAnalysisTests(unittest.TestCase):
    def test_linear_growth_measured_by_engine_not_process_wall(self):
        rows = scaling.analyze([
            report(1, 100.0, 100.0),
            report(2, 200.0, 110.0),
            report(4, 400.0, 125.0),
        ], min_duration_ms=50.0)
        self.assertEqual(len(rows), 1)
        self.assertTrue(math.isclose(rows[0]["time_exponent"], 1.0, abs_tol=1e-12))
        self.assertEqual(rows[0]["rss_delta_mib"], 25.0)
        self.assertIn("1.00", scaling.markdown(rows, 50.0))

    def test_quadratic_growth_is_suspicious(self):
        rows = scaling.analyze([
            report(1, 75.0), report(2, 300.0), report(4, 1200.0),
        ])
        self.assertAlmostEqual(rows[0]["time_exponent"], 2.0, places=6)

    def test_small_in_engine_times_are_not_ranked(self):
        rows = scaling.analyze([report(1, 2.0), report(2, 8.0)])
        self.assertIsNone(rows[0]["time_exponent"])

    def test_failed_points_do_not_produce_fabricated_growth(self):
        rows = scaling.analyze([
            report(1, 150.0), report(2, None, status="failed"),
        ])
        self.assertEqual(rows[0]["status"], "failed")
        self.assertIsNone(rows[0]["time_exponent"])

    def test_reject_nonpositive_minimum_duration(self):
        with self.assertRaises(ValueError):
            scaling.analyze([], min_duration_ms=0.0)


if __name__ == "__main__":
    unittest.main()
