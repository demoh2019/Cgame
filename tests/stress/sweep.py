#!/usr/bin/env python3
"""Run stress scenarios at several scales and rank nonlinear performance growth.

This calls run.py for every scale: each engine workload remains in its own
timeout- and RSS-limited process. Only standard-library modules are needed.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import math
from pathlib import Path
import subprocess
import sys
from typing import Any


def parse_scales(value: str) -> list[int]:
    try:
        values = [int(item.strip()) for item in value.split(",")]
    except ValueError as exc:
        raise argparse.ArgumentTypeError("scales must be comma-separated integers") from exc
    if len(values) < 2 or len(values) != len(set(values)) or any(v < 1 or v > 1000 for v in values):
        raise argparse.ArgumentTypeError("provide at least two distinct scales in [1, 1000]")
    return sorted(values)


def summarize_scaling(reports: list[dict[str, Any]], threshold_pct: float) -> dict[str, Any]:
    """Compare load points only when the workload configurations match."""
    if len(reports) < 2:
        raise ValueError("at least two reports required")
    config = reports[0]["configuration"]
    baseline_cases = set(reports[0]["cases"])
    rows: list[dict[str, Any]] = []
    failures: list[str] = []
    for report in reports:
        other = report["configuration"]
        for key in ("render_mode", "frames", "seed", "repeats"):
            if config.get(key) != other.get(key):
                raise ValueError("inconsistent configuration: " + key)
        if set(report["cases"]) != baseline_cases:
            raise ValueError("the case set differs between load points")
    scales = [int(report["configuration"]["scale"]) for report in reports]
    if sorted(set(scales)) != scales:
        raise ValueError("scales must be strictly increasing")
    ratio = scales[-1] / scales[0]
    for case in sorted(baseline_cases):
        cases = [report["cases"][case] for report in reports]
        detail = {"case": case, "scales": scales, "points": []}
        for scale, item in zip(scales, cases):
            engine_times = [run["engine"]["duration_ms"] for run in item.get("runs", [])
                            if run.get("status") == "passed" and "engine" in run]
            engine_time = None
            if engine_times:
                engine_times.sort()
                center = len(engine_times) // 2
                engine_time = (engine_times[center] if len(engine_times) % 2
                               else (engine_times[center - 1] + engine_times[center]) / 2)
            detail["points"].append({
                "scale": scale, "status": item.get("status"),
                "median_engine_ms": engine_time,
                "median_wall_seconds": item.get("median_wall_seconds"),
                "max_rss_mib": item.get("max_rss_mib"),
            })
        if any(item.get("status") != "passed" for item in cases):
            failures.append(case + ": failed at one or more scales")
            detail["status"] = "failed"
        else:
            detail["status"] = "passed"
        for field in ("median_engine_ms", "median_wall_seconds"):
            first, last = detail["points"][0][field], detail["points"][-1][field]
            if (isinstance(first, (int, float)) and isinstance(last, (int, float))
                    and math.isfinite(first) and math.isfinite(last) and first > 0 and last >= 0):
                excess = ((last / first) / ratio - 1.0) * 100.0
                detail[field + "_growth_excess_pct"] = round(excess, 3)
            else:
                detail[field + "_growth_excess_pct"] = None
        rss_first = detail["points"][0]["max_rss_mib"]
        rss_last = detail["points"][-1]["max_rss_mib"]
        detail["rss_delta_mib"] = (round(rss_last - rss_first, 3)
                                  if rss_first is not None and rss_last is not None else None)
        detail["worst_growth_excess_pct"] = max(
            (detail[key] for key in ("median_engine_ms_growth_excess_pct",
                                     "median_wall_seconds_growth_excess_pct") if detail[key] is not None),
            default=None,
        )
        if (detail["status"] == "passed" and detail["median_engine_ms_growth_excess_pct"] is not None
                and detail["median_engine_ms_growth_excess_pct"] > threshold_pct):
            detail["warning"] = "engine time grew superlinearly"
        rows.append(detail)
    rows.sort(key=lambda row: (row["worst_growth_excess_pct"] is None,
                               -(row["worst_growth_excess_pct"] or 0), row["case"]))
    return {"cases": rows, "failures": failures, "threshold_pct": threshold_pct}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True)
    parser.add_argument("--scales", type=parse_scales, default=[1, 2, 4])
    parser.add_argument("--preset", choices=("smoke", "standard", "soak", "brutal"), default="smoke")
    parser.add_argument("--case", action="append", default=[])
    parser.add_argument("--render-mode", choices=("headless", "display"), default="headless")
    parser.add_argument("--repeats", type=int, default=3)
    parser.add_argument("--frames", type=int)
    parser.add_argument("--timeout", type=float)
    parser.add_argument("--rss-limit-mib", type=float)
    parser.add_argument("--seed", type=int, default=12345)
    parser.add_argument("--threshold-pct", type=float, default=30.0)
    parser.add_argument("--fail-on-superlinear", action="store_true")
    parser.add_argument("--output", type=Path, default=Path("stress-scaling.json"))
    args = parser.parse_args(argv)
    if args.repeats < 1 or args.threshold_pct < 0:
        parser.error("repeats must be positive and threshold nonnegative")
    reports: list[dict[str, Any]] = []
    errors: list[str] = []
    run_dir = args.output.with_name(args.output.stem + "-runs")
    run_dir.mkdir(parents=True, exist_ok=True)
    for scale in args.scales:
        file_path = run_dir / ("scale-%d.json" % scale)
        command = [sys.executable, str(Path(__file__).with_name("run.py")),
                   "--godot", args.godot, "--preset", args.preset,
                   "--render-mode", args.render_mode, "--scale", str(scale),
                   "--seed", str(args.seed), "--repeats", str(args.repeats),
                   "--output", str(file_path)]
        for case in args.case:
            command += ["--case", case]
        for option, value in (("--frames", args.frames), ("--timeout", args.timeout),
                              ("--rss-limit-mib", args.rss_limit_mib)):
            if value is not None:
                command += [option, str(value)]
        print("Scale %d: running %s" % (scale, args.preset), flush=True)
        with (run_dir / ("scale-%d.log" % scale)).open("w", encoding="utf-8") as output:
            process = subprocess.run(command, stdout=output, stderr=subprocess.STDOUT, check=False)
        if file_path.is_file():
            try:
                reports.append(json.loads(file_path.read_text(encoding="utf-8")))
            except (OSError, ValueError) as exc:
                errors.append("scale %d: invalid report: %s" % (scale, exc))
        else:
            errors.append("scale %d: report missing (exit %d)" % (scale, process.returncode))
        if process.returncode and file_path.is_file():
            errors.append("scale %d: one or more engine workloads failed" % scale)
    comparison: dict[str, Any] = {}
    if len(reports) == len(args.scales):
        try:
            comparison = summarize_scaling(reports, args.threshold_pct)
            errors.extend(comparison["failures"])
        except (ValueError, KeyError, TypeError) as exc:
            errors.append("invalid comparison: %s" % exc)
    else:
        errors.append("not all scale results were recorded")
    if args.fail_on_superlinear:
        errors.extend(row["case"] + ": " + row["warning"] for row in comparison.get("cases", [])
                      if row.get("warning"))
    report = {"schema_version": 1, "created_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
              "configuration": {"scales": args.scales, "preset": args.preset,
                                "render_mode": args.render_mode, "repeats": args.repeats},
              "comparison": comparison, "failures": errors, "status": "failed" if errors else "passed"}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    tmp = args.output.with_name(args.output.name + ".tmp")
    tmp.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    tmp.replace(args.output)
    print("Highest nonlinear growth (engine time / scale):")
    for item in comparison.get("cases", [])[:15]:
        print("  %-24s %s%%" % (item["case"], item["median_engine_ms_growth_excess_pct"]))
    for error in errors:
        print("FAIL: " + error, file=sys.stderr)
    print("Report: %s (%s)" % (args.output, report["status"]))
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
