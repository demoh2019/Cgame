#!/usr/bin/env python3
"""Compare Cgame/Albion After screenshot benchmark logs without inventing GPU FPS.

Usage:
    python tools/compare_frame_pacing.py before.log after.log
    python tools/compare_frame_pacing.py before.log after.log --max-p95-regression-pct 10

Capture the same scene, camera, quality preset, resolution and hardware both
times. Native viewport GPU timestamps may be delayed and are independent from
the process-frame CPU delta series.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

PREFIX = "CGAME_FRAME_BENCHMARK "
METRICS = ("p50_ms", "p95_ms", "p99_ms")


def read_report(path: Path) -> dict[str, Any]:
    report = None
    for line in path.read_text(encoding="utf-8").splitlines():
        position = line.find(PREFIX)
        if position < 0:
            continue
        value = json.loads(line[position + len(PREFIX):])
        if not isinstance(value, dict) or not isinstance(value.get("cpu"), dict):
            raise ValueError(f"{path}: malformed benchmark record")
        if not isinstance(value.get("gpu"), dict):
            raise ValueError(f"{path}: missing GPU summary (zero samples are valid)")
        report = value
    if report is None:
        raise ValueError(f"{path}: no {PREFIX.strip()} record found")
    return report


def pct_change(before: float, after: float) -> float:
    if before <= 0 or not all(map(lambda v: abs(v) != float("inf") and v == v, (before, after))):
        raise ValueError("benchmark values must be finite and positive")
    return 100.0 * (after - before) / before


def compare(before: dict[str, Any], after: dict[str, Any]) -> str:
    left_method = str(before.get("render_method", ""))
    right_method = str(after.get("render_method", ""))
    if not left_method or left_method != right_method:
        raise ValueError("renderer changed between runs; GPU measurements are not comparable")
    lines = [f"Renderer: {left_method}",
             "Use identical hardware, scene, camera, resolution and quality; no speedup is claimed without controlled measurements."]
    for device, title in (("cpu", "CPU process-frame interval"),
                          ("gpu", "GPU viewport render duration (not display FPS)")):
        left = before[device]
        right = after[device]
        a_count, b_count = int(left.get("count", 0)), int(right.get("count", 0))
        lines.append(f"{title}: {a_count} -> {b_count} valid samples")
        if a_count == 0 or b_count == 0:
            lines.append("  unavailable in one or both captures (no fabricated values)")
            continue
        for metric in METRICS:
            old = float(left[metric])
            new = float(right[metric])
            lines.append(f"  {metric}: {old:.2f} -> {new:.2f} ms ({pct_change(old, new):+.1f}%)")
        if device == "cpu":
            old_low = float(left["one_percent_low_fps"])
            new_low = float(right["one_percent_low_fps"])
            lines.append(f"  1% low FPS (slowest 1% mean): {old_low:.1f} -> {new_low:.1f}")
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("before", type=Path, help="log from the baseline build")
    parser.add_argument("after", type=Path, help="log from the candidate build")
    parser.add_argument("--max-p95-regression-pct", type=float, default=None,
                        help="optional CI regression cap; requires >=30 samples per compared stream")
    args = parser.parse_args(argv)
    try:
        before = read_report(args.before)
        after = read_report(args.after)
        print(compare(before, after))
        if args.max_p95_regression_pct is not None:
            cap = args.max_p95_regression_pct
            if not (0.0 <= cap < float("inf")):
                raise ValueError("--max-p95-regression-pct must be a finite nonnegative number")
            for device in ("cpu", "gpu"):
                b, a = before[device], after[device]
                if min(int(b.get("count", 0)), int(a.get("count", 0))) == 0:
                    continue
                if min(int(b["count"]), int(a["count"])) < 30:
                    raise ValueError(f"{device}: at least 30 valid samples required for a regression gate")
                if pct_change(float(b["p95_ms"]), float(a["p95_ms"])) > cap:
                    print(f"REGRESSION: {device} p95 rose by more than {cap:g}%")
                    return 1
    except (OSError, KeyError, TypeError, ValueError, json.JSONDecodeError) as exc:
        parser.exit(2, f"Comparison unavailable: {exc}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
