#!/usr/bin/env python3
"""Long-lived, in-process Cgame memory soak for allocator-retention investigation.

Each scenario is a single Godot process running many allocation/free cycles.
This is a diagnostic, not proof of a memory leak. Uses the standard stress
watchdog for process RSS and time limits.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import math
import os
from pathlib import Path
import statistics
import sys
from typing import Any

import run as stress

SCENARIOS = ("nodes", "packed")


def analyze_samples(samples: list[int]) -> dict[str, float | int]:
    """Compare robust early/late windows after warmup, and fit a linear trend."""
    if len(samples) < 4 or any(
        isinstance(v, bool) or not isinstance(v, (int, float))
        or not math.isfinite(v) or v < 0 for v in samples
    ):
        raise ValueError("Expected at least four valid nonnegative memory samples")
    warmup = max(1, len(samples) // 10)
    retained = samples[warmup:]
    window = max(2, len(retained) // 5)
    first = statistics.median(retained[:window])
    last = statistics.median(retained[-window:])
    center = (len(retained) - 1) / 2.0
    mean = statistics.mean(retained)
    denom = sum((i - center) ** 2 for i in range(len(retained)))
    slope = sum((i - center) * (value - mean) for i, value in enumerate(retained)) / denom
    mib = 1048576.0
    return {
        "warmup_cycles": warmup,
        "window_cycles": window,
        "early_median_mib": round(first / mib, 4),
        "late_median_mib": round(last / mib, 4),
        "retained_growth_mib": round((last - first) / mib, 4),
        "trend_mib_per_cycle": round(slope / mib, 6),
        "peak_engine_static_mib": round(max(samples) / mib, 4),
    }


def build_command(binary: str, project: Path, scenario: str, batch: int,
                  cycles: int, seed: int) -> list[str]:
    if scenario not in SCENARIOS:
        raise ValueError("Unknown memory soak scenario: " + scenario)
    return [
        binary, "--headless", "--path", str(project), "--script",
        "res://memory_soak.gd", "--no-header", "--",
        "--case=memory_soak", "--scenario=" + scenario,
        "--scale=" + str(batch), "--frames=" + str(cycles),
        "--seed=" + str(seed),
    ]


def run_scenario(binary: str, project: Path, scenario: str, batch: int,
                 cycles: int, seed: int, timeout: float,
                 rss_limit_mib: float, growth_limit_mib: float | None) -> dict[str, Any]:
    cmd = build_command(binary, project, scenario, batch, cycles, seed)
    result = stress.run_once(cmd, timeout, rss_limit_mib, "memory_soak", batch, cycles, seed)
    if result["status"] != "passed":
        return result
    detail = result["engine"]["detail"]
    if detail.get("scenario") != scenario or detail.get("cycles") != cycles or detail.get("batch") != batch:
        result["status"] = "failed"
        result["failure"] = "invalid_scenario_metadata"
        return result
    try:
        samples = detail["engine_static_memory_bytes"]
        if not isinstance(samples, list) or len(samples) != cycles:
            raise ValueError("Unexpected engine-memory sample count")
        result["memory_analysis"] = analyze_samples(samples)
    except (KeyError, TypeError, ValueError) as exc:
        result["status"] = "failed"
        result["failure"] = "invalid_memory_samples: %s" % exc
        return result
    if growth_limit_mib is not None and result["memory_analysis"]["retained_growth_mib"] > growth_limit_mib:
        result["status"] = "failed"
        result["failure"] = "retained_memory_growth_exceeded"
    return result


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN", "./bin/godot.linuxbsd.editor.dev.x86_64"))
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parent)
    parser.add_argument("--scenario", action="append", choices=SCENARIOS,
                        help="Repeat to select scenarios; default nodes and packed")
    parser.add_argument("--cycles", type=int, default=300)
    parser.add_argument("--batch", type=int, default=300)
    parser.add_argument("--repeats", type=int, default=3)
    parser.add_argument("--seed", type=int, default=12345)
    parser.add_argument("--timeout", type=float, default=900.0)
    parser.add_argument("--rss-limit-mib", type=float, default=4096.0)
    parser.add_argument("--max-retained-growth-mib", type=float,
                        help="Optional absolute retained growth limit after warmup")
    parser.add_argument("--output", type=Path, default=Path("memory-soak.json"))
    args = parser.parse_args(argv)
    if (not 4 <= args.cycles <= 100000 or not 1 <= args.batch <= 1000
            or not 1 <= args.repeats <= 100 or args.timeout <= 0
            or args.rss_limit_mib <= 0 or (args.max_retained_growth_mib is not None
            and args.max_retained_growth_mib < 0)):
        parser.error("Invalid memory-soak cycles, batch, repeats or safety limits")
    project = args.project.resolve()
    if not (project / "memory_soak.gd").is_file() or not (project / "project.godot").is_file():
        parser.error("Missing tests/stress memory_soak.gd or project.godot")
    binary = str(Path(args.godot).resolve()) if "/" in args.godot or "\\" in args.godot else args.godot
    scenarios = list(dict.fromkeys(args.scenario or SCENARIOS))
    report: dict[str, Any] = {
        "schema_version": 1,
        "created_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "configuration": {
            "scenarios": scenarios, "cycles": args.cycles, "batch": args.batch,
            "repeats": args.repeats, "rss_limit_mib": args.rss_limit_mib,
            "timeout_seconds": args.timeout, "growth_limit_mib": args.max_retained_growth_mib,
        },
        "results": {}, "failures": [],
    }
    for scenario in scenarios:
        runs = []
        for i in range(args.repeats):
            print("[%s] soak %d/%d" % (scenario, i + 1, args.repeats), flush=True)
            run = run_scenario(binary, project, scenario, args.batch, args.cycles,
                               args.seed, args.timeout, args.rss_limit_mib,
                               args.max_retained_growth_mib)
            runs.append(run)
            if run["status"] != "passed":
                report["failures"].append("%s #%d: %s" % (scenario, i + 1, run.get("failure")))
        growth = [r["memory_analysis"]["retained_growth_mib"] for r in runs
                  if r["status"] == "passed"]
        report["results"][scenario] = {
            "status": "passed" if all(r["status"] == "passed" for r in runs) else "failed",
            "median_retained_growth_mib": round(statistics.median(growth), 4) if growth else None,
            "runs": runs,
        }
    report["status"] = "failed" if report["failures"] else "passed"
    args.output.parent.mkdir(parents=True, exist_ok=True)
    tmp = args.output.with_name(args.output.name + ".tmp")
    tmp.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    tmp.replace(args.output)
    print("Memory soak: %s (%s)" % (args.output, report["status"]))
    for problem in report["failures"]:
        print("FAIL: " + problem, file=sys.stderr)
    return 1 if report["failures"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
