"""Regression tests for the cross-platform process-RSS watchdog.

Run with: python3 -m unittest discover -s tests/stress -p 'test_*.py'
No Godot executable is needed.
"""
import subprocess
import sys
import unittest
from unittest.mock import patch

import run as stress


class MacOSResidentMemoryTests(unittest.TestCase):
    def test_ps_sampling_is_rate_limited(self):
        self.assertEqual(stress.sampling_interval_seconds("darwin", False), 0.25)
        self.assertEqual(stress.sampling_interval_seconds("darwin", True), 0.05)
        self.assertEqual(stress.sampling_interval_seconds("linux", False), 0.05)

    def test_ps_kib_is_converted_to_mib(self):
        result = subprocess.CompletedProcess(["ps"], 0, "65536\n", "")
        with patch.object(stress.subprocess, "run", return_value=result) as call:
            self.assertEqual(stress.macos_ps_rss_mib(12345), 64.0)
        self.assertEqual(call.call_args.args[0], ["ps", "-o", "rss=", "-p", "12345"])
        self.assertEqual(call.call_args.kwargs["timeout"], 1.0)

    def test_ps_failure_is_not_mistaken_for_zero_rss(self):
        for code, output in ((1, ""), (0, ""), (0, "invalid")):
            with self.subTest(code=code, output=output):
                result = subprocess.CompletedProcess(["ps"], code, output, "")
                with patch.object(stress.subprocess, "run", return_value=result):
                    self.assertIsNone(stress.macos_ps_rss_mib(12345))

    def test_ps_timeout_returns_unavailable(self):
        with patch.object(stress.subprocess, "run",
                          side_effect=subprocess.TimeoutExpired(["ps"], 1)):
            self.assertIsNone(stress.macos_ps_rss_mib(12345))


class WatchdogEnforcementTests(unittest.TestCase):
    def test_missing_rss_monitor_fails_long_running_child(self):
        with patch.object(stress, "sample_process_tree", return_value=(None, None, 0)):
            result = stress.run_once(
                [sys.executable, "-c", "import time; time.sleep(3)"],
                5.0, 1024.0, "containers", 1, 12, 12345)
        self.assertEqual(result["status"], "failed", result)
        self.assertEqual(result["failure"], "rss_monitor_unavailable")

    def test_excessive_rss_fails_immediately(self):
        with patch.object(stress, "sample_process_tree", return_value=(2048.0, 1.0, 1)):
            result = stress.run_once(
                [sys.executable, "-c", "import time; time.sleep(3)"],
                5.0, 1024.0, "containers", 1, 12, 12345)
        self.assertEqual(result["status"], "failed", result)
        self.assertEqual(result["failure"], "rss_limit_exceeded")


if __name__ == "__main__":
    unittest.main()
