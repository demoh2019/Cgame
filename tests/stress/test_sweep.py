"""Unit tests for load-curve analysis (no Godot binary required)."""
import json
from pathlib import Path
import tempfile
import unittest

import sweep


def _stage(scale, time_ms, rss_mib, *, durations=None, frame_ms=None, failed=False):
    durations = durations if durations is not None else [time_ms] * 3
    runs = []
    for value in durations:
        detail = {} if frame_ms is None else {"peak_physics_ms": frame_ms}
        runs.append({
            "status": "passed", "wall_seconds": value / 1000.0 + 0.5,
            "cpu_seconds": value / 1000.0, "peak_rss_mib": rss_mib,
            "engine": {"duration_ms": value, "detail": detail},
        })
    if failed:
        runs.append({"status": "failed", "failure": "timeout", "peak_rss_mib": rss_mib})
    return {
        "configuration": {"scale": scale},
        "cases": {"math": {"status": "failed" if failed else "passed", "runs": runs}},
    }


class InputTests(unittest.TestCase):
    def test_strictly_increasing_scales(self):
        self.assertEqual(sweep.parse_scales("1, 3,8"), [1, 3, 8])
        for bad in ("", "1,1", "4,2", "0,2", "1,nan", "1,1001"):
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                sweep.parse_scales(bad)

    def test_reject_report_missing_case_or_wrong_scale(self):
        with self.assertRaisesRegex(ValueError, "scale"):
            sweep.analyze({3: _stage(2, 10, 100)}, ["math"])
        with self.assertRaisesRegex(ValueError, "missing"):
            sweep.analyze({1: _stage(1, 10, 100)}, ["physics_2d"])

    def test_reject_different_frame_counts_across_scales(self):
        first, second = _stage(1, 10, 100), _stage(2, 20, 110)
        first["configuration"]["frames"] = 60
        second["configuration"]["frames"] = 120
        with self.assertRaisesRegex(ValueError, "configuration mismatch"):
            sweep.analyze({1: first, 2: second}, ["math"])


class CurveTests(unittest.TestCase):
    def test_flags_superlinear_cpu_without_process_startup_noise(self):
        reports = {
            1: _stage(1, 20, 100),
            2: _stage(2, 42, 110),
            4: _stage(4, 180, 170),
        }
        row = sweep.analyze(reports, ["math"])["cases"]["math"]
        kinds = {f["type"] for f in row["findings"]}
        self.assertIn("superlinear_cpu", kinds)
        self.assertIn("superlinear_rss", kinds)

    def test_near_linear_workload_is_not_flagged(self):
        reports = {i: _stage(i, i * 10.0 + 5.0, 120 + i * 3)
                   for i in (1, 2, 4)}
        result = sweep.analyze(reports, ["math"])
        self.assertEqual(result["ranked_suspects"], [])
        self.assertEqual(result["failures"], [])

    def test_frame_budget_and_failed_runs(self):
        reports = {1: _stage(1, 20, 120, frame_ms=25.0, failed=True)}
        result = sweep.analyze(reports, ["math"])
        self.assertEqual(result["failures"], ["math"])
        self.assertEqual({f["type"] for f in result["cases"]["math"]["findings"]},
                         {"failure", "frame_budget"})

    def test_detects_high_variance_with_three_samples(self):
        reports = {1: _stage(1, 10, 120, durations=[10, 11, 40])}
        findings = sweep.analyze(reports, ["math"])["cases"]["math"]["findings"]
        self.assertIn("jitter", {f["type"] for f in findings})

    def test_markdown_is_populated(self):
        report = sweep.analyze({1: _stage(1, 12, 100)}, ["math"])
        md = sweep.render_markdown(report)
        self.assertIn("math | 1 | 12.0 | 100.0", md)
        self.assertIn("GPU frame time", md)


class OfflineTests(unittest.TestCase):
    def test_cli_analyzes_reports_and_saves_json_and_markdown(self):
        with tempfile.TemporaryDirectory() as dirname:
            tmp = Path(dirname)
            stages = []
            for scale in (1, 2):
                path = tmp / ("scale_%d.json" % scale)
                path.write_text(json.dumps(_stage(scale, scale * 8.0, 100 + 2 * scale)))
                stages.append(str(path))
            output = tmp / "summary.json"
            rc = sweep.main(["--reports", *stages, "--case", "math",
                             "--output", str(output)])
            self.assertEqual(rc, 0)
            self.assertTrue(output.is_file())
            self.assertTrue(output.with_suffix(".md").is_file())
            self.assertEqual(json.loads(output.read_text())["scales"], [1, 2])

    def test_cli_strict_mode_fails_on_suspected_issue(self):
        with tempfile.TemporaryDirectory() as dirname:
            tmp = Path(dirname)
            path = tmp / "scale_1.json"
            path.write_text(json.dumps(_stage(1, 10, 100, frame_ms=50)))
            rc = sweep.main(["--reports", str(path), "--case", "math",
                             "--fail-on-bottleneck", "--output", str(tmp / "result.json")])
            self.assertEqual(rc, 1)


if __name__ == "__main__":
    unittest.main()
