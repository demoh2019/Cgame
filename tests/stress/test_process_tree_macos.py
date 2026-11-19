"""Unit tests for BSD ps aggregation of macOS engine subprocess trees."""
import subprocess
import unittest
from unittest.mock import patch

import process_tree


class MacOSProcessTreeTests(unittest.TestCase):
    def test_ps_cpu_time_formats(self):
        self.assertAlmostEqual(process_tree._ps_time_seconds("03:04.50"), 184.5)
        self.assertAlmostEqual(process_tree._ps_time_seconds("01:02:03"), 3723.0)
        self.assertAlmostEqual(process_tree._ps_time_seconds("1-02:03:04.5"), 93784.5)

    def test_collects_descendants_without_unrelated_processes(self):
        snapshot = (
            "100 1 10240 00:00:01.00\n"
            "101 100 2048 00:00:02.50\n"
            "102 101 512 00:00:00.50\n"
            "88 1 999999 00:59:00\n"
        )
        completed = subprocess.CompletedProcess(["ps"], 0, snapshot, "")
        with patch.object(process_tree.subprocess, "run", return_value=completed) as spy:
            rss, cpu, count = process_tree._macos_ps_usage(100)
        self.assertAlmostEqual(rss, 12.5)
        self.assertAlmostEqual(cpu, 4.0)
        self.assertEqual(count, 3)
        self.assertEqual(spy.call_args.args[0], ["ps", "-axo", "pid=,ppid=,rss=,time="])

    def test_skips_malformed_and_unknown_root(self):
        snapshot = "12 1 invalid 00:00:00\n13 1 512 00:00:01.00\n"
        completed = subprocess.CompletedProcess(["ps"], 0, snapshot, "")
        with patch.object(process_tree.subprocess, "run", return_value=completed):
            self.assertEqual(process_tree._macos_ps_usage(999), (None, None, 0))
            self.assertEqual(process_tree._macos_ps_usage(13), (0.5, 1.0, 1))

    def test_ps_failure_and_timeout_are_missing_samples(self):
        failed = subprocess.CompletedProcess(["ps"], 1, "", "")
        with patch.object(process_tree.subprocess, "run", return_value=failed):
            self.assertEqual(process_tree._macos_ps_usage(100), (None, None, 0))
        with patch.object(process_tree.subprocess, "run",
                          side_effect=subprocess.TimeoutExpired("ps", 2.0)):
            self.assertEqual(process_tree._macos_ps_usage(100), (None, None, 0))


if __name__ == "__main__":
    unittest.main()
