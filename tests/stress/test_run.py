"""Standard-library unit tests for the stress orchestration layer."""
import json
from pathlib import Path
import sys
import tempfile
import unittest

import run as stress


def result_payload(case="containers", scale=1, frames=12, seed=12345, detail=None):
    return {
        "case": case, "scale": scale, "frames": frames, "seed": seed,
        "duration_ms": 13.2, "detail": {} if detail is None else detail,
    }


class CaseSelectionTests(unittest.TestCase):
    def test_headless_all_skips_render_but_includes_physics(self):
        selected = stress.choose_cases([], "headless")
        self.assertIn("physics_2d", selected)
        self.assertIn("physics_3d", selected)
        self.assertNotIn("render_2d", selected)

    def test_display_all_includes_render(self):
        self.assertEqual(stress.choose_cases(["all"], "display"), list(stress.CASES))

    def test_duplicates_and_comma_syntax(self):
        self.assertEqual(stress.choose_cases(["math,stream", "math"], "headless"), ["math", "stream"])

    def test_unavailable_render_is_error(self):
        with self.assertRaisesRegex(ValueError, "requires --render-mode display"):
            stress.choose_cases(["render_3d"], "headless")

    def test_unknown_case_is_error(self):
        with self.assertRaisesRegex(ValueError, "Unknown"):
            stress.choose_cases(["missing"], "display")

    def test_command_passes_user_arguments_after_delimiter(self):
        cmd = stress.build_command("godot", Path("/tmp/project"), "math", 3, 4, 5, "headless", [])
        self.assertIn("--headless", cmd)
        self.assertEqual(cmd[cmd.index("--") + 1:], [
            "--case=math", "--scale=3", "--frames=4", "--seed=5"])
        self.assertNotIn("--headless", stress.build_command(
            "godot", Path("/tmp/project"), "render_2d", 1, 1, 1, "display", []))


class ResultsTests(unittest.TestCase):
    def test_valid_marker(self):
        payload = result_payload()
        text = "Godot Engine\n" + stress.PREFIX + json.dumps(payload) + "\n"
        self.assertEqual(stress.parse_result(text, "containers", 1, 12, 12345), payload)

    def test_reject_missing_or_duplicate_marker(self):
        with self.assertRaisesRegex(ValueError, "exactly one"):
            stress.parse_result("not a marker", "containers", 1, 12, 12345)
        marker = stress.PREFIX + json.dumps(result_payload())
        with self.assertRaisesRegex(ValueError, "exactly one"):
            stress.parse_result(marker + "\n" + marker, "containers", 1, 12, 12345)

    def test_reject_wrong_seed_and_engine_error(self):
        marker = stress.PREFIX + json.dumps(result_payload())
        with self.assertRaisesRegex(ValueError, "seed"):
            stress.parse_result(marker, "containers", 1, 12, 99)
        error = stress.PREFIX + json.dumps(result_payload(detail={"error": "corrupt"}))
        with self.assertRaisesRegex(ValueError, "failed"):
            stress.parse_result(error, "containers", 1, 12, 12345)

    def test_reject_bad_duration(self):
        payload = result_payload()
        payload["duration_ms"] = -1.0
        with self.assertRaisesRegex(ValueError, "Negative"):
            stress.parse_result(stress.PREFIX + json.dumps(payload), "containers", 1, 12, 12345)

    def test_p95_and_failed_runs(self):
        rows = [{"status": "passed", "wall_seconds": v, "peak_rss_mib": 10.0} for v in (1., 2., 3., 4., 5.)]
        stats = stress.summarize(rows)
        self.assertEqual(stats["median_wall_seconds"], 3.)
        self.assertEqual(stats["p95_wall_seconds"], 5.)
        rows.append({"status": "failed", "wall_seconds": 0.5, "peak_rss_mib": 15.})
        stats = stress.summarize(rows)
        self.assertEqual(stats["status"], "failed")
        self.assertEqual(stats["max_rss_mib"], 15.)

    def test_empty_measurements(self):
        self.assertIsNone(stress.summarize([{"status": "failed", "peak_rss_mib": None}])["median_wall_seconds"])


class BaselineTests(unittest.TestCase):
    def make_report(self, time_value=1.0, rss=100.0):
        return {
            "configuration": {"preset": "smoke", "scale": 1, "frames": 12, "render_mode": "headless"},
            "cases": {"math": {
                "status": "passed", "median_wall_seconds": time_value, "max_rss_mib": rss,
                "runs": [],
            }},
        }

    def test_regression_flags_wall_and_memory(self):
        old = self.make_report()
        new = self.make_report(1.5, 140.0)
        failures = stress.compare_baseline(new, old, 20., None)
        self.assertEqual(len(failures), 2)

    def test_small_variance_passes(self):
        self.assertEqual(stress.compare_baseline(
            self.make_report(1.10, 110.), self.make_report(), 20., None), [])

    def test_configuration_must_match(self):
        old = self.make_report()
        new = self.make_report()
        new["configuration"]["scale"] = 5
        with self.assertRaisesRegex(ValueError, "mismatch"):
            stress.compare_baseline(new, old, 20., None)

    def test_memory_churn_threshold(self):
        current = self.make_report()
        current["cases"]["memory_churn"] = {"status": "passed", "runs": [
            {"status": "passed", "engine": {"detail": {"retained_growth_bytes": 4 * 1048576}}},
        ]}
        failures = stress.compare_baseline(current, self.make_report(), 20., 2.)
        self.assertEqual(len(failures), 1)


class ProcessIsolationTests(unittest.TestCase):
    def test_valid_child_output(self):
        payload = json.dumps(result_payload())
        script = "print(" + repr(stress.PREFIX + payload) + ")"
        actual = stress.run_once([sys.executable, "-c", script], 5., 1024.,
                                 "containers", 1, 12, 12345)
        self.assertEqual(actual["status"], "passed", actual)
        self.assertEqual(actual["engine"]["duration_ms"], 13.2)

    def test_logged_engine_error_fails_even_on_zero_exit(self):
        payload = json.dumps(result_payload())
        script = "print('ERROR: runtime failure');print(" + repr(stress.PREFIX + payload) + ")"
        actual = stress.run_once([sys.executable, "-c", script], 5., 1024.,
                                 "containers", 1, 12, 12345)
        self.assertEqual(actual["status"], "failed")
        self.assertEqual(actual["failure"], "engine_error_log")

    def test_engine_log_error_pattern(self):
        self.assertIsNotNone(stress.ENGINE_ERROR.search("SCRIPT ERROR: bad script"))
        self.assertIsNotNone(stress.ENGINE_ERROR.search("E 0:00:00:000 bad resource"))
        self.assertIsNone(stress.ENGINE_ERROR.search("WARNING: harmless note"))

    def test_child_crash(self):
        actual = stress.run_once([sys.executable, "-c", "import sys;sys.exit(7)"],
                                 5., 1024., "containers", 1, 12, 12345)
        self.assertEqual(actual["status"], "failed")
        self.assertEqual(actual["failure"], "engine_exit_7")

    def test_timeout_watchdog(self):
        actual = stress.run_once([sys.executable, "-c", "import time;time.sleep(2)"],
                                 0.15, 1024., "containers", 1, 12, 12345)
        self.assertEqual(actual["failure"], "timeout")

    def test_missing_binary_is_reported(self):
        actual = stress.run_once(["/definitely/missing/stress-engine"], 1., 1024.,
                                 "containers", 1, 12, 12345)
        self.assertEqual(actual["status"], "failed")
        self.assertIn("launch", actual["failure"])


class EscalationTests(unittest.TestCase):
    def test_bounded_ramp_and_overflow(self):
        self.assertEqual(stress.ramp_scales(2, 4, 3), [2, 6, 18, 54])
        self.assertEqual(stress.ramp_scales(900, 10, 2), [900])
        self.assertEqual(stress.ramp_scales(100, 5, 3), [100, 300, 900])
        for args in ((0, 2, 2), (1, 0, 2), (1, 2, 1)):
            with self.assertRaises(ValueError):
                stress.ramp_scales(*args)

    def test_hotspot_ranking_excludes_failed_workloads(self):
        report = {"cases": {
            "fast": {"status": "passed", "median_wall_seconds": 1.,
                     "max_rss_mib": 20., "max_p95_frame_ms": 2.0},
            "slow": {"status": "passed", "median_wall_seconds": 4.,
                     "max_rss_mib": 10., "max_p95_frame_ms": 8.0},
            "broken": {"status": "failed", "median_wall_seconds": 1000.,
                       "max_rss_mib": 1000.},
        }}
        ranked = stress.ranking(report)
        self.assertEqual([x["case"] for x in ranked["median_wall_seconds"]],
                         ["slow", "fast"])
        self.assertEqual([x["case"] for x in ranked["max_rss_mib"]],
                         ["fast", "slow"])
        self.assertEqual([x["case"] for x in ranked["max_p95_frame_ms"]],
                         ["slow", "fast"])

    def test_summary_records_engine_frame_tail(self):
        runs = [{"status": "passed", "wall_seconds": 0.4, "peak_rss_mib": 13.0,
                 "rss_post_warmup_growth_mib": 2.5,
                 "engine": {"detail": {
                     "frame_latency_ms": {"p95": 12.0},
                     "physics_latency_ms": {"p95": 4.0},
                 }}}]
        summary = stress.summarize(runs)
        self.assertEqual(summary["max_p95_frame_ms"], 12.0)
        self.assertEqual(summary["max_p95_physics_ms"], 4.0)
        self.assertEqual(summary["max_post_warmup_rss_growth_mib"], 2.5)

    def test_cli_escalates_and_stops_at_first_failure(self):
        from unittest import mock

        observed = []

        def fake_run(command, timeout, rss, case, scale, frames, seed):
            observed.append(scale)
            if scale >= 4:
                return {"status": "failed", "wall_seconds": 0.05,
                        "peak_rss_mib": 5.0, "failure": "synthetic limit"}
            return {"status": "passed", "wall_seconds": 0.05,
                    "peak_rss_mib": 5.0, "cpu_seconds": 0.04,
                    "engine": result_payload(case=case, scale=scale, frames=frames, seed=seed)}

        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "report.json"
            with mock.patch.object(stress, "run_once", side_effect=fake_run):
                rc = stress.main(["--godot", "fake-godot",
                                  "--project", str(Path(__file__).resolve().parent),
                                  "--case", "math", "--scale", "2",
                                  "--ramp", "--ramp-steps", "4",
                                  "--repeats", "2", "--output", str(output)])
            data = json.loads(output.read_text(encoding="utf-8"))
            self.assertEqual(rc, 1)
            self.assertEqual(observed, [2, 2, 4])
            self.assertIn("math@2", data["cases"])
            self.assertIn("math@4", data["cases"])
            self.assertNotIn("math@8", data["cases"])
            self.assertTrue(data["configuration"]["ramp"])
            self.assertEqual(data["status"], "failed")


if __name__ == "__main__":
    unittest.main()
