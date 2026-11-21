"""Tests for the engine-wide benchmark comparison utility (no GPU required)."""
import contextlib
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from compare_frame_pacing import PREFIX, compare, main, pct_change, read_report


def record(cpu_ms=10.0, gpu_ms=8.0, gpu_count=120, method="gl_compatibility"):
    def sample(ms, count=120):
        return {"count": count, "p50_ms": ms * 0.8, "p95_ms": ms,
                "p99_ms": ms * 1.2, "one_percent_low_fps": 1000.0 / (ms * 1.2)}
    return {"render_method": method, "cpu": sample(cpu_ms),
            "gpu": sample(gpu_ms, gpu_count)}


class FramePacingComparisonTest(unittest.TestCase):
    def test_cpu_gpu_are_separate(self):
        text = compare(record(20, 10), record(16, 12))
        self.assertIn("cpu", text.lower())
        self.assertIn("GPU viewport render duration (not display FPS)", text)
        self.assertIn("p95_ms: 20.00 -> 16.00 ms (-20.0%)", text)
        self.assertIn("p95_ms: 10.00 -> 12.00 ms (+20.0%)", text)

    def test_missing_gpu_is_explicit(self):
        self.assertIn("unavailable", compare(record(gpu_count=0), record(gpu_count=0)))
        with self.assertRaisesRegex(ValueError, "renderer changed"):
            compare(record(method="forward_plus"), record(method="gl_compatibility"))

    def test_invalid_baseline(self):
        with self.assertRaises(ValueError):
            pct_change(0.0, 10.0)

    def test_parser_uses_latest_record(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "capture.log"
            path.write_text("hello\n" + PREFIX + json.dumps(record(30)) +
                            "\n" + PREFIX + json.dumps(record(12)) + "\n", encoding="utf-8")
            self.assertEqual(read_report(path)["cpu"]["p95_ms"], 12)

    def test_regression_gate(self):
        with tempfile.TemporaryDirectory() as tmp:
            before, after = Path(tmp) / "before.log", Path(tmp) / "after.log"
            before.write_text(PREFIX + json.dumps(record(10)), encoding="utf-8")
            after.write_text(PREFIX + json.dumps(record(15)), encoding="utf-8")
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(main([str(before), str(after), "--max-p95-regression-pct", "10"]), 1)
            after.write_text(PREFIX + json.dumps(record(9)), encoding="utf-8")
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(main([str(before), str(after), "--max-p95-regression-pct", "10"]), 0)

    def test_no_benchmark(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "empty.log"
            path.write_text("no records", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "no CGAME_FRAME_BENCHMARK"):
                read_report(path)


if __name__ == "__main__":
    unittest.main()
