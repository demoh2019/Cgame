#!/usr/bin/env python3
"""Run load curves for every Cgame stress case and rank observed bottlenecks.

Uses run.py for per-process isolation, RSS watchdogs and raw measurements.
Reports are evidence, not proof of leaks or a replacement for profiler traces.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import math
import os
from pathlib import Path
import statistics
import subprocess
import sys
from typing import Any

import run as stress


def parse_scales(value: str) -> list[int]:
    try:
        scales = [int(v.strip()) for v in value.split(",")]
    except ValueError as exc:
        raise ValueError("Scales must be comma-separated integers") from exc
    if not scales or any(v < 1 or v > 1000 for v in scales):
        raise ValueError("Scales must be in [1, 1000]")
    if scales != sorted(set(scales)):
        raise ValueError("Scales must be unique and strictly increasing")
    return scales


def _median(values: list[float]) -> float | None:
    return round(statistics.median(values), 4) if values else None


def _measure(case_data: dict[str, Any], scale: int) -> dict[str, Any]:
    runs = case_data.get("runs", [])
    good = [r for r in runs if r.get("status") == "passed" and isinstance(r.get("engine"), dict)]
    ms = [float(r["engine"]["duration_ms"]) for r in good]
    cpu = [float(r["cpu_seconds"]) for r in good if r.get("cpu_seconds") is not None]
    rss = [float(r["peak_rss_mib"]) for r in runs if r.get("peak_rss_mib") is not None]
    frames = [
        float(r["engine"]["detail"][key])
        for r in good
        for key in ("peak_frame_ms", "peak_physics_ms")
        if isinstance(r["engine"].get("detail", {}).get(key), (int, float))
    ]
    spread = 0.0
    if len(ms) >= 3 and statistics.median(ms) > 0:
        spread = 100.0 * (
            sorted(ms)[math.ceil(0.95 * len(ms)) - 1] - statistics.median(ms)
        ) / statistics.median(ms)
    return {
        "scale": scale,
        "status": "passed" if good and len(good) == len(runs) else "failed",
        "successful_runs": len(good),
        "total_runs": len(runs),
        "engine_median_ms": _median(ms),
        "cpu_median_seconds": _median(cpu),
        "peak_rss_mib": round(max(rss), 3) if rss else None,
        "worst_frame_ms": round(max(frames), 3) if frames else None,
        "p95_over_median_pct": round(spread, 2) if len(ms) >= 3 else None,
        "failures": [str(r.get("failure", "unknown")) for r in runs if r.get("status") != "passed"],
    }


def analyze(reports: dict[int, dict[str, Any]], cases: list[str], *,
            nonlinear_factor: float = 1.5, jitter_percent: float = 30.0,
            frame_budget_ms: float = 16.67) -> dict[str, Any]:
    """Compare like-for-like workloads. Heuristics are reported as suspects."""
    if not reports:
        raise ValueError("No load-stage reports")
    for scale, report in reports.items():
        configuration = report.get("configuration", {})
        if configuration.get("scale") != scale:
            raise ValueError("Report scale does not match its stage")
        if set(cases) - set(report.get("cases", {})):
            raise ValueError("Report is missing requested cases at scale %d" % scale)
    # Comparing different builds, frame counts or host environments creates
    # misleading nonlinear curves. Missing optional metadata stays compatible
    # with older reports, but mismatched populated fields are always rejected.
    first_report = reports[min(reports)]
    for scale, report in reports.items():
        for field in ("preset", "frames", "repeats", "seed", "render_mode"):
            actual = report.get("configuration", {}).get(field)
            expected = first_report.get("configuration", {}).get(field)
            if actual != expected:
                raise ValueError("Report configuration mismatch: %s at scale %d" % (field, scale))
        for field in ("platform", "processor", "logical_cpus"):
            if report.get("host", {}).get(field) != first_report.get("host", {}).get(field):
                raise ValueError("Report host mismatch: %s at scale %d" % (field, scale))
        if report.get("godot_binary") != first_report.get("godot_binary"):
            raise ValueError("Report binary mismatch at scale %d" % scale)
    ordered = sorted(reports)
    rows: dict[str, Any] = {}
    suspects: list[dict[str, Any]] = []
    for case in cases:
        points = [_measure(reports[scale]["cases"][case], scale) for scale in ordered]
        findings: list[dict[str, Any]] = []
        for p in points:
            if p["status"] != "passed":
                findings.append({"type": "failure", "scale": p["scale"],
                                 "detail": ", ".join(p["failures"]) or "No successful samples"})
            if p["worst_frame_ms"] is not None and p["worst_frame_ms"] > frame_budget_ms:
                findings.append({"type": "frame_budget", "scale": p["scale"],
                                 "observed_ms": p["worst_frame_ms"],
                                 "budget_ms": frame_budget_ms})
            if (p["p95_over_median_pct"] is not None and
                    p["p95_over_median_pct"] > jitter_percent):
                findings.append({"type": "jitter", "scale": p["scale"],
                                 "observed_pct": p["p95_over_median_pct"]})
        for previous, current in zip(points, points[1:]):
            older, newer = previous["engine_median_ms"], current["engine_median_ms"]
            if older is not None and older > 0 and newer is not None:
                growth = (newer / older) / (current["scale"] / previous["scale"])
                # Avoid elevating timer resolution and tiny fixed-cost changes.
                if growth > nonlinear_factor and newer - older >= 2.0:
                    findings.append({"type": "superlinear_cpu", "from_scale": previous["scale"],
                                     "to_scale": current["scale"], "per_unit_growth": round(growth, 3)})
        # Subtract fixed process startup and engine memory. Compare marginal RSS
        # density per added unit of scale, rather than raw RSS ratios.
        for first, second, third in zip(points, points[1:], points[2:]):
            a, b, c = (p["peak_rss_mib"] for p in (first, second, third))
            if None in (a, b, c):
                continue
            older_density = (b - a) / (second["scale"] - first["scale"])
            newer_density = (c - b) / (third["scale"] - second["scale"])
            if older_density > 1.0 and c - b >= 16.0 and newer_density > older_density * nonlinear_factor:
                findings.append({"type": "superlinear_rss", "from_scale": second["scale"],
                                 "to_scale": third["scale"],
                                 "marginal_growth": round(newer_density / older_density, 3)})
        severity = sum({"failure": 100, "superlinear_cpu": 20, "superlinear_rss": 20,
                        "frame_budget": 10, "jitter": 5}[f["type"]] for f in findings)
        rows[case] = {"points": points, "findings": findings, "severity": severity}
        if findings:
            suspects.append({"case": case, "severity": severity, "findings": findings})
    suspects.sort(key=lambda row: (-row["severity"], row["case"]))
    return {"scales": ordered, "cases": rows, "ranked_suspects": suspects,
            "failures": [row["case"] for row in suspects
                         if any(f["type"] == "failure" for f in row["findings"])]}


def render_markdown(summary: dict[str, Any]) -> str:
    lines = [
        "# Cgame load-curve bottleneck report", "",
        "Heuristic suspects ranked by severity. Investigate with a profiler before optimizing.",
        "CPU time is **engine scenario duration** (not process startup time).",
        "RSS is sampled whole-process memory; short peaks may be missed.",
        "A frame-budget finding uses engine process/physics monitors, **not GPU frame time**.",
        "",
        "| Case | Scale | Engine median (ms) | Peak RSS (MiB) | Frame peak (ms) | Finding |",
        "| --- | ---: | ---: | ---: | ---: | --- |",
    ]
    prioritized = [item["case"] for item in summary["ranked_suspects"]]
    prioritized += [name for name in summary["cases"] if name not in prioritized]
    for name in prioritized:
        row = summary["cases"][name]
        kinds = ", ".join(sorted(set(f["type"] for f in row["findings"]))) or "none"
        for point in row["points"]:
            def fmt(value: Any) -> str:
                return "-" if value is None else str(value)
            lines.append("| %s | %d | %s | %s | %s | %s |" % (
                name, point["scale"], fmt(point["engine_median_ms"]),
                fmt(point["peak_rss_mib"]), fmt(point["worst_frame_ms"]), kinds,
            ))
    lines += ["", "## Ranked suspects", ""]
    if summary["ranked_suspects"]:
        for row in summary["ranked_suspects"]:
            lines.append("- **%s** (severity %d): %s" % (
                row["case"], row["severity"],
                ", ".join("%s@%s" % (
                    f["type"], f.get("scale", f.get("to_scale", "?")))
                    for f in row["findings"])))
    else:
        lines.append("No warnings at the chosen thresholds; this is not proof of no bottlenecks.")
    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN", "./bin/godot.linuxbsd.editor.dev.x86_64"))
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parent)
    parser.add_argument("--render-mode", choices=("headless", "display"), default="headless")
    parser.add_argument("--case", action="append", default=[], help="Comma-separated cases, or all")
    parser.add_argument("--scales", default="1,2,4,8", help="Increasing workload multipliers, each <= 1000")
    parser.add_argument("--repeats", type=int, default=3)
    parser.add_argument("--frames", type=int, default=90)
    parser.add_argument("--timeout", type=float, default=240.0)
    parser.add_argument("--rss-limit-mib", type=float, default=4096.0)
    parser.add_argument("--seed", type=int, default=12345)
    parser.add_argument("--godot-arg", action="append", default=[],
                        help="Forward an extra argument to the Godot binary")
    parser.add_argument("--nonlinear-factor", type=float, default=1.5)
    parser.add_argument("--jitter-percent", type=float, default=30.0)
    parser.add_argument("--frame-budget-ms", type=float, default=16.67)
    parser.add_argument("--fail-on-bottleneck", action="store_true",
                        help="Exit nonzero for suspected inefficiency, in addition to actual failures")
    parser.add_argument("--reports", type=Path, nargs="+",
                        help="Analyze existing run.py JSON reports without running the engine")
    parser.add_argument("--output", type=Path, default=Path("out/stress-sweep.json"))
    args = parser.parse_args(argv)
    try:
        scales = parse_scales(args.scales)
        cases = stress.choose_cases(args.case, args.render_mode)
    except ValueError as exc:
        parser.error(str(exc))
    if (args.repeats < 1 or args.frames < 1 or args.frames > 100000
            or args.timeout <= 0 or args.rss_limit_mib <= 0
            or args.nonlinear_factor <= 1 or args.jitter_percent <= 0
            or args.frame_budget_ms <= 0):
        parser.error("Invalid limits or anomaly thresholds")

    reports: dict[int, dict[str, Any]] = {}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    if args.reports:
        for path in args.reports:
            try:
                report = json.loads(path.read_text(encoding="utf-8"))
                scale = int(report["configuration"]["scale"])
                if scale in reports:
                    raise ValueError("Duplicate scale %d" % scale)
                reports[scale] = report
            except (OSError, ValueError, KeyError, TypeError) as exc:
                parser.error("Invalid report %s: %s" % (path, exc))
    else:
        for scale in scales:
            stage_path = args.output.with_name("%s-scale-%d.json" % (args.output.stem, scale))
            cmd = [
                sys.executable, str(Path(__file__).with_name("run.py")),
                "--godot", args.godot, "--project", str(args.project),
                "--preset", "smoke", "--render-mode", args.render_mode,
                "--scale", str(scale), "--frames", str(args.frames),
                "--repeats", str(args.repeats), "--timeout", str(args.timeout),
                "--rss-limit-mib", str(args.rss_limit_mib), "--seed", str(args.seed),
                "--output", str(stage_path),
            ]
            for case in cases:
                cmd.extend(("--case", case))
            for option in args.godot_arg:
                cmd.extend(("--godot-arg", option))
            print("Load stage x%d (%d scenarios, %d repeats)" % (
                scale, len(cases), args.repeats), flush=True)
            # Never consume a stale report when the child runner fails.
            stage_path.unlink(missing_ok=True)
            completed = subprocess.run(cmd, check=False)
            if not stage_path.is_file():
                print("Runner failed to create report at scale %d (exit %d)" % (
                    scale, completed.returncode), file=sys.stderr)
                return 1
            reports[scale] = json.loads(stage_path.read_text(encoding="utf-8"))

    try:
        summary = analyze(reports, cases, nonlinear_factor=args.nonlinear_factor,
                          jitter_percent=args.jitter_percent,
                          frame_budget_ms=args.frame_budget_ms)
    except (ValueError, KeyError, TypeError) as exc:
        parser.error(str(exc))
    summary["created_utc"] = dt.datetime.now(dt.timezone.utc).isoformat()
    summary["configuration"] = {
        "render_mode": args.render_mode, "repeats": args.repeats,
        "frames": args.frames, "nonlinear_factor": args.nonlinear_factor,
        "jitter_percent": args.jitter_percent, "frame_budget_ms": args.frame_budget_ms,
    }
    summary["status"] = "failed" if summary["failures"] else "passed"
    args.output.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    md_path = args.output.with_suffix(".md")
    md_path.write_text(render_markdown(summary), encoding="utf-8")
    print("Analysis: %s; markdown: %s; suspects: %d; failed cases: %d" % (
        args.output, md_path, len(summary["ranked_suspects"]), len(summary["failures"])))
    return int(bool(summary["failures"] or (args.fail_on_bottleneck and summary["ranked_suspects"])))


if __name__ == "__main__":
    raise SystemExit(main())
