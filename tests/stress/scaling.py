#!/usr/bin/env python3
"""Multi-scale performance sweep for finding superlinear engine workloads.

Each scale runs the existing isolated watchdog harness. The reported growth
exponent is diagnostic: workload sizes, warm caches and startup costs differ.
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
import statistics
import subprocess
import sys
from typing import Any

import run as harness


def parse_scales(text: str) -> list[int]:
    try:
        result = [int(x.strip()) for x in text.split(",")]
    except ValueError as exc:
        raise ValueError("scales must be comma-separated integers") from exc
    if len(result) < 2 or len(result) > 8 or any(s < 1 or s > 1000 for s in result):
        raise ValueError("choose 2-8 scales in the range 1..1000")
    if result != sorted(set(result)):
        raise ValueError("scales must be strictly increasing and unique")
    return result


def analyze(reports: list[dict[str, Any]], min_duration_ms: float = 50.0) -> list[dict[str, Any]]:
    """Estimate log-log time growth using within-case medians.

    Skip unreliable exponents when the smallest valid engine measurement is
    below min_duration_ms; small workloads are dominated by measurement noise.
    """
    if min_duration_ms <= 0:
        raise ValueError("min_duration_ms must be positive")
    case_names = sorted({name for report in reports for name in report.get("cases", {})})
    results = []
    for name in case_names:
        points = []
        for report in reports:
            scale = report.get("configuration", {}).get("scale")
            summary = report.get("cases", {}).get(name)
            if not isinstance(scale, int) or scale <= 0 or not isinstance(summary, dict):
                continue
            ms = summary.get("median_engine_ms")
            rss = summary.get("max_rss_mib")
            if not isinstance(ms, (int, float)) or not math.isfinite(ms) or ms < 0:
                ms = None
            if not isinstance(rss, (int, float)) or not math.isfinite(rss) or rss < 0:
                rss = None
            points.append({
                "scale": scale, "engine_ms": ms, "rss_mib": rss,
                "status": summary.get("status", "unknown"),
            })
        points.sort(key=lambda point: point["scale"])
        valid = [p for p in points if p["status"] == "passed" and p["engine_ms"] is not None]
        exponent = None
        if len(valid) >= 2 and valid[0]["engine_ms"] >= min_duration_ms:
            slopes = []
            for a, b in zip(valid, valid[1:]):
                if a["engine_ms"] > 0 and b["engine_ms"] > 0 and a["scale"] < b["scale"]:
                    slopes.append(math.log(b["engine_ms"] / a["engine_ms"]) /
                                  math.log(b["scale"] / a["scale"]))
            if slopes:
                exponent = statistics.median(slopes)
        rss_points = [p for p in points if p["rss_mib"] is not None]
        rss_delta = (rss_points[-1]["rss_mib"] - rss_points[0]["rss_mib"]
                     if len(rss_points) >= 2 else None)
        results.append({
            "case": name, "points": points, "time_exponent": exponent,
            "rss_delta_mib": rss_delta,
            "status": "passed" if points and all(p["status"] == "passed" for p in points)
            else "failed",
        })
    return sorted(results, key=lambda r: (
        r["status"] == "passed",
        r["time_exponent"] is None,
        -(r["time_exponent"] or 0),
    ))


def markdown(rows: list[dict[str, Any]], min_duration_ms: float) -> str:
    lines = [
        "# Cgame multi-scale bottleneck analysis",
        "",
        "Each row compares **the same isolated engine scenario** across scales.",
        "Estimated slope is a median adjacent log-log exponent: approximately 1",
        "means near-linear time growth; significantly above 1 suggests extra work",
        "per input unit. This is a diagnostic, **not proof of algorithmic complexity**.",
        "",
        "| Scenario | Status | Engine ms at each scale | Growth exponent | RSS delta MiB |",
        "| --- | --- | --- | ---: | ---: |",
    ]
    for row in rows:
        timings = ", ".join(
            "%s: %s" % (p["scale"], "%.2f" % p["engine_ms"] if p["engine_ms"] is not None else "n/a")
            for p in row["points"]
        )
        power = "%.2f" % row["time_exponent"] if row["time_exponent"] is not None else "n/a"
        rss = "%.1f" % row["rss_delta_mib"] if row["rss_delta_mib"] is not None else "n/a"
        lines.append("| `%s` | %s | %s | %s | %s |" %
                     (row["case"], row["status"], timings, power, rss))
    lines.extend([
        "", "An exponent requires at least two successful, distinct scale points",
        "and a first in-engine duration >= %.1f ms." % min_duration_ms,
        "Start CPU/GPU/heap profiling with high-exponent scenarios, then confirm",
        "with repeated runs on identical hardware, settings and build flags.",
        "Per-scenario RSS is process resident memory; it includes fixed engine",
        "overhead and is not a heap-leak measurement. Rendering scenarios need",
        "a real display/GPU; headless cannot measure graphics performance.",
        "",
    ])
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default="./bin/godot.linuxbsd.editor.dev.x86_64")
    parser.add_argument("--scales", default="1,2,4,8", help="2-8 strictly increasing load multipliers")
    parser.add_argument("--case", action="append", default=[],
                        help="Case list(s) accepted by run.py; default all headless cases")
    parser.add_argument("--render-mode", choices=("headless", "display"), default="headless")
    parser.add_argument("--repeats", type=int, default=2)
    parser.add_argument("--frames", type=int, default=60)
    parser.add_argument("--seed", type=int, default=12345)
    parser.add_argument("--timeout", type=float, default=300.0)
    parser.add_argument("--rss-limit-mib", type=float, default=4096.0)
    parser.add_argument("--min-duration-ms", type=float, default=50.0)
    parser.add_argument("--flag-exponent", type=float, default=None,
                        help="Optional failure threshold for a credible superlinear growth exponent")
    parser.add_argument("--output-dir", type=Path, default=Path("stress-scaling"))
    args = parser.parse_args(argv)
    try:
        scales = parse_scales(args.scales)
        cases = harness.choose_cases(args.case, args.render_mode)
    except ValueError as exc:
        parser.error(str(exc))
    if (args.repeats < 1 or args.repeats > 20 or args.frames < 1 or
            args.timeout <= 0 or args.rss_limit_mib <= 0 or args.min_duration_ms <= 0 or
            (args.flag_exponent is not None and args.flag_exponent <= 0)):
        parser.error("repeats, frames and all safety thresholds must be positive")
    args.output_dir.mkdir(parents=True, exist_ok=True)
    reports = []
    failed_scales = []
    for scale in scales:
        output = args.output_dir / ("scale_%d.json" % scale)
        # Never reuse a previous run after a failed or interrupted launch.
        if output.exists():
            output.unlink()
        cmd = [
            sys.executable, str(Path(__file__).resolve().with_name("run.py")),
            "--godot", args.godot, "--preset", "smoke", "--scale", str(scale),
            "--frames", str(args.frames), "--repeats", str(args.repeats),
            "--timeout", str(args.timeout), "--rss-limit-mib", str(args.rss_limit_mib),
            "--seed", str(args.seed), "--render-mode", args.render_mode,
            "--case", ",".join(cases), "--output", str(output),
        ]
        completed = subprocess.run(cmd, check=False)
        if completed.returncode:
            failed_scales.append(scale)
        if output.is_file():
            reports.append(json.loads(output.read_text(encoding="utf-8")))
        else:
            failed_scales.append(scale)
    rows = analyze(reports, args.min_duration_ms)
    findings = [row["case"] for row in rows
                if row["time_exponent"] is not None and args.flag_exponent is not None
                and row["time_exponent"] > args.flag_exponent]
    result = {
        "schema_version": 1, "scales": scales, "cases": cases,
        "min_duration_ms": args.min_duration_ms,
        "flag_exponent": args.flag_exponent, "failed_scales": sorted(set(failed_scales)),
        "superlinear_flags": findings, "results": rows,
    }
    (args.output_dir / "sweep.json").write_text(
        json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    (args.output_dir / "sweep.md").write_text(markdown(rows, args.min_duration_ms), encoding="utf-8")
    print("Scaling report: %s" % (args.output_dir / "sweep.md"))
    if findings:
        print("Superlinear flags: " + ", ".join(findings), file=sys.stderr)
    return 1 if failed_scales or findings or any(row["status"] != "passed" for row in rows) else 0


if __name__ == "__main__":
    raise SystemExit(main())
