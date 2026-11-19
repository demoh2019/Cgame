"""Standard-library unit tests for the stress orchestration layer."""
import json
from pathlib import Path
import sys
import tempfile
import unittest

import run as stress
import editor_import as importer


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

    def test_curve_stress_cases_are_selectable_and_headless(self):
        cases = ("curve_tessellation_2d", "curve_tessellation_3d")
        self.assertEqual(stress.choose_cases([",".join(cases)], "headless"), list(cases))
        self.assertTrue(set(cases).issubset(stress.choose_cases(["all"], "headless")))

    def test_lifecycle_scenarios_available(self):
        self.assertEqual(stress.choose_cases(["object_lifecycle,scene_churn"], "headless"),
                         ["object_lifecycle", "scene_churn"])

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

    def test_p99_wall_measurement(self):
        samples = [{"status": "passed", "wall_seconds": v, "peak_rss_mib": 10.0} for v in (1., 2., 3.)]
        self.assertEqual(stress.summarize(samples)["p99_wall_seconds"], 3.0)

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

    def test_engine_time_regression_without_wall_regression(self):
        baseline = self.make_report()
        current = self.make_report()
        baseline["cases"]["math"]["median_engine_ms"] = 100.0
        current["cases"]["math"]["median_engine_ms"] = 150.0
        self.assertEqual(len(stress.compare_baseline(current, baseline, 20., None)), 1)

    def test_hotspots_rank_and_explain_resource_pressure(self):
        report = self.make_report()
        report["status"] = "passed"
        report["failures"] = []
        report["configuration"]["rss_limit_mib"] = 100.0
        report["cases"]["math"].update({"p95_wall_seconds": 1.9, "median_engine_ms": 50.0})
        report["cases"]["io"] = {
            "median_wall_seconds": 2.0, "p95_wall_seconds": 2.1,
            "max_rss_mib": 95.0, "median_engine_ms": 1800.0,
        }
        text = stress.markdown_hotspots(report)
        self.assertLess(text.index("| io |"), text.index("| math |"))
        self.assertIn("near RSS limit", text)
        self.assertIn("high run-to-run variability", text)
        self.assertIn("startup/teardown dominates", text)

    def test_retained_growth_covers_lifecycle_and_scene_churn(self):
        current = self.make_report()
        for name in ("object_lifecycle", "scene_churn"):
            current["cases"][name] = {"status": "passed", "runs": [
                {"status": "passed", "engine": {"detail": {
                    "retained_growth_bytes": 3 * 1048576}}},
            ]}
        errors = stress.compare_baseline(current, self.make_report(), 20., 2.)
        self.assertEqual(len(errors), 2)
        self.assertTrue(any("object_lifecycle" in error for error in errors))
        self.assertTrue(any("scene_churn" in error for error in errors))

    def test_rss_scope_mismatch_rejected(self):
        baseline = self.make_report()
        current = self.make_report()
        current["configuration"]["rss_scope"] = "process_tree"
        with self.assertRaisesRegex(ValueError, "rss_scope"):
            stress.compare_baseline(current, baseline, 20.0, None)

    def test_memory_churn_threshold(self):
        current = self.make_report()
        current["cases"]["memory_churn"] = {"status": "passed", "runs": [
            {"status": "passed", "engine": {"detail": {"retained_growth_bytes": 4 * 1048576}}},
        ]}
        failures = stress.compare_baseline(current, self.make_report(), 20., 2.)
        self.assertEqual(len(failures), 1)


class RegistryTests(unittest.TestCase):
    def test_python_and_gdscript_case_registries_match(self):
        import re
        script = Path(__file__).with_name("stress.gd").read_text(encoding="utf-8")
        registry = script.split("const CASES := [", 1)[1].split("]", 1)[0]
        gd_cases = re.findall(r'"([^"]+)"', registry)
        self.assertEqual(len(gd_cases), len(set(gd_cases)))
        self.assertEqual(set(gd_cases), set(stress.CASES))


class AbsoluteBudgetTests(unittest.TestCase):
    def make_case(self, detail):
        return {"stress": {"runs": [
            {"status": "passed", "engine": {"detail": detail}},
        ]}}

    def test_spikes_and_vram_over_budget(self):
        suite = self.make_case({
            "peak_frame_ms": 31., "peak_physics_ms": 26.,
            "peak_video_memory_bytes": 300 * 1048576,
        })
        failures = stress.check_absolute_limits(suite, 16., 20., 256.)
        self.assertEqual(len(failures), 3)

    def test_budgets_ignored_when_unreported(self):
        suite = self.make_case({"checksum": 42})
        self.assertEqual(stress.check_absolute_limits(suite, 1., 1., 1.), [])

    def test_compliant_budgets(self):
        suite = self.make_case({
            "peak_frame_ms": 12., "peak_physics_ms": 14.,
            "peak_video_memory_bytes": 128 * 1048576,
        })
        self.assertEqual(stress.check_absolute_limits(suite, 16., 20., 256.), [])

    def test_nan_or_negative_metric_caught(self):
        suite = self.make_case({"peak_frame_ms": float("nan"), "peak_physics_ms": -1.})
        failures = stress.check_absolute_limits(suite, 16., 20., None)
        self.assertEqual(len(failures), 2)

    def test_failed_process_not_double_reported(self):
        suite = {"stress": {"runs": [{"status": "failed", "engine": {
            "detail": {"peak_frame_ms": 900.}}}]}}
        self.assertEqual(stress.check_absolute_limits(suite, 16., None, None), [])


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


class ImportProjectTests(unittest.TestCase):
    def test_png_is_valid_and_decodes(self):
        import struct
        import zlib

        png = importer.make_png(16, 12, 7)
        self.assertEqual(png[:8], b"\x89PNG\r\n\x1a\n")
        pos = 8
        chunks = {}
        while pos < len(png):
            size = struct.unpack(">I", png[pos:pos + 4])[0]
            name = png[pos + 4:pos + 8]
            body = png[pos + 8:pos + 8 + size]
            self.assertEqual(
                struct.unpack(">I", png[pos + 8 + size:pos + 12 + size])[0],
                zlib.crc32(name + body) & 0xffffffff,
            )
            chunks.setdefault(name, []).append(body)
            pos += 12 + size
        self.assertEqual(struct.unpack(">II", chunks[b"IHDR"][0][:8]), (16, 12))
        self.assertEqual(len(zlib.decompress(chunks[b"IDAT"][0])), 12 * (1 + 16 * 4))

    def test_reproducible_png_generation(self):
        a = importer.make_png(32, 16, 43)
        self.assertEqual(a, importer.make_png(32, 16, 43))
        self.assertNotEqual(a, importer.make_png(32, 16, 44))

    def test_synthetic_project_has_valid_references(self):
        with tempfile.TemporaryDirectory() as temp:
            project = Path(temp)
            meta = importer.make_project(project, 3, 7, 17)
            self.assertEqual(meta, {"textures": 3, "scripts": 7, "scenes": 7})
            self.assertTrue((project / "project.godot").exists())
            for i in range(7):
                scene = (project / "scenes" / ("scene_%05d.tscn" % i)).read_text()
                self.assertIn("res://textures/texture_%05d.png" % (i % 3), scene)
                self.assertIn("res://scripts/script_%05d.gd" % i, scene)
            self.assertEqual(len(list((project / "textures").glob("*.png"))), 3)

    def test_import_invocation_uses_isolated_directory(self):
        with tempfile.TemporaryDirectory() as temp:
            project = Path(temp)
            payload = 'STRESS_RESULT: irrelevant'
            # Run a synthetic Python child to verify that marker validation
            # is explicitly disabled for editor import subprocesses.
            result = stress.run_once(
                [sys.executable, "-c", "print('Import finished')"],
                5., 1024., "cold", 1, 1, 0, require_marker=False)
            self.assertEqual(result["status"], "passed", result)


if __name__ == "__main__":
    unittest.main()
