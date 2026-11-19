"""Check isolated process groups and child-inclusive RAM limits without Godot."""
import os
import subprocess
import sys
import time
import unittest

import process_tree
import run as stress


@unittest.skipUnless(sys.platform.startswith("linux"), "Requires Linux /proc")
class ProcessTreeTests(unittest.TestCase):
    def test_missing_pid(self):
        self.assertEqual(process_tree.sample(999999999), (None, None, 0))

    def test_isolated_group_terminates(self):
        proc = subprocess.Popen(
            [sys.executable, "-c", "import time;time.sleep(8)"],
            **process_tree.isolation_options(),
        )
        try:
            self.assertEqual(os.getpgid(proc.pid), proc.pid)
        finally:
            process_tree.kill_group(proc)
            proc.wait(timeout=4)
        self.assertNotEqual(proc.returncode, 0)

    def test_descendant_rss_triggers_watchdog(self):
        worker = (
            "data = bytearray(64 * 1024 * 1024)\n"
            "for i in range(0, len(data), 4096): data[i] = 1\n"
            "import time;time.sleep(8)\n"
        )
        parent = (
            "import subprocess,sys,time\n"
            "subprocess.Popen([sys.executable, '-c', " + repr(worker) + "])\n"
            "time.sleep(8)\n"
        )
        outcome = stress.run_once(
            [sys.executable, "-c", parent], 4.0, 40.0,
            "containers", 1, 12, 12345, require_marker=False,
        )
        self.assertEqual(outcome["failure"], "rss_limit_exceeded", outcome)
        self.assertGreaterEqual(outcome["peak_processes"], 2)
        self.assertGreater(outcome["peak_rss_mib"], 40.0)

    def test_child_included_in_aggregate(self):
        worker = (
            "data = bytearray(64 * 1024 * 1024)\n"
            "for i in range(0, len(data), 4096): data[i] = 1\n"
            "import time;time.sleep(8)\n"
        )
        parent = (
            "import subprocess,sys,time\n"
            "subprocess.Popen([sys.executable,'-c'," + repr(worker) + "])\n"
            "time.sleep(8)\n"
        )
        proc = subprocess.Popen(
            [sys.executable, "-c", parent], **process_tree.isolation_options(),
        )
        try:
            seen = False
            deadline = time.monotonic() + 4.0
            while time.monotonic() < deadline:
                rss, cpu, count = process_tree.sample(proc.pid)
                if count > 1 and rss is not None and rss > 48.0:
                    self.assertIsNotNone(cpu)
                    seen = True
                    break
                time.sleep(0.05)
            self.assertTrue(seen, "Child RSS must count toward parent workload")
        finally:
            process_tree.kill_group(proc)
            proc.wait(timeout=4)


if __name__ == "__main__":
    unittest.main()
