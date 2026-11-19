#!/usr/bin/env python3
"""Summarize measured stress bottlenecks and same-workload performance regressions."""
from __future__ import annotations

import argparse
import csv
import io
import json
import math
from pathlib import Path
from statistics import median
from typing import Any


def valid_number(value: Any) -> float | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        return None
    return float(value)


def percent_change(new: Any, old: Any) -> float | None:
    a, b = valid_number(new), valid_number(old)
    return 100.0 * (a / b - 1.0) if a is not None and b is not None and b > 0 else None


def engine_median(data: dict[str, Any]) -> float | None:
    value = valid_number(data.get("median_engine_ms"))
    if value is not None:
        return value
    values = [v for run in data.get("runs", []) if run.get("status") == "passed"
              if (v := valid_number(run.get("engine", {}).get("duration_ms"))) is not None]
    return median(values) if values else None


def frame_p95(data: dict[str, Any]) -> float | None:
    values = [v for run in data.get("runs", []) if run.get("status") == "passed"
              if (v := valid_number(run.get("engine", {}).get("detail", {})
                                    .get("frame_interval_ms", {}).get("p95"))) is not None]
    return max(values) if values else None  # Max of per-run p95, NOT pooled percentile.


def analyze(report: dict[str, Any], baseline: dict[str, Any] | None = None,
            *, regression_pct: float = 20.0, frame_limit_ms: float = 33.3,
            rss_limit_mib: float = 2048.0) -> list[dict[str, Any]]:
    if report.get("schema_version") != 1 or not isinstance(report.get("cases"), dict):
        raise ValueError("Expected stress report schema_version=1 and cases object")
    if baseline is not None:
        if baseline.get("schema_version") != 1 or not isinstance(baseline.get("cases"), dict):
            raise ValueError("Invalid baseline report")
        for key in ("preset", "scale", "frames", "render_mode", "seed"):
            if report.get("configuration", {}).get(key) != baseline.get("configuration", {}).get(key):
                raise ValueError("Incompatible workload baseline: " + key)
    rows = []
    for name, data in report["cases"].items():
        past = baseline["cases"].get(name) if baseline else None
        wall = valid_number(data.get("median_wall_seconds"))
        engine = engine_median(data)
        rss = valid_number(data.get("max_rss_mib"))
        cpu = valid_number(data.get("median_cpu_seconds"))
        frame = frame_p95(data)
        dw = percent_change(wall, past.get("median_wall_seconds")) if past else None
        de = percent_change(engine, engine_median(past)) if past else None
        dm = percent_change(rss, past.get("max_rss_mib")) if past else None
        problems = []
        priority = 0
        if data.get("status") != "passed":
            problems.append("FAILED (crash, timeout, resource cap, or invalid result)")
            priority = 100
        for metric, delta in (("engine time", de), ("wall time", dw), ("resident RAM", dm)):
            if delta is not None and delta > regression_pct:
                problems.append("%s regression +%.1f%%" % (metric, delta))
                priority = max(priority, 80 + min(15, int(delta / 20)))
        if frame is not None and frame > frame_limit_ms:
            problems.append("frame interval p95 %.2f ms > %.2f ms" % (frame, frame_limit_ms))
            priority = max(priority, 60)
        if rss is not None and rss > rss_limit_mib:
            problems.append("RSS %.1f MiB > %.1f MiB" % (rss, rss_limit_mib))
            priority = max(priority, 40)
        cores = cpu / wall if cpu is not None and wall and wall > 0 else None
        if cores is not None and cores >= 0.85:
            problems.append("CPU-intensive (%.2f core equivalents)" % cores)
            priority = max(priority, 10)
        rows.append({"case": name, "status": data.get("status", "unknown"),
                     "priority": priority, "wall_s": wall, "engine_ms": engine,
                     "frame_p95_ms": frame, "peak_rss_mib": rss,
                     "cpu_core_equivalents": cores, "wall_delta_pct": dw,
                     "engine_delta_pct": de, "rss_delta_pct": dm,
                     "findings": "; ".join(problems) or "no thresholds exceeded"})
    rows.sort(key=lambda row: (-row["priority"], -(row["wall_s"] or 0), row["case"]))
    return rows


FIELDS = ("case", "status", "priority", "wall_s", "engine_ms", "frame_p95_ms",
          "peak_rss_mib", "cpu_core_equivalents", "wall_delta_pct",
          "engine_delta_pct", "rss_delta_pct", "findings")


def as_csv(rows: list[dict[str, Any]]) -> str:
    output = io.StringIO(newline="")
    writer = csv.DictWriter(output, fieldnames=FIELDS)
    writer.writeheader()
    writer.writerows(rows)
    return output.getvalue()


def as_markdown(rows: list[dict[str, Any]], has_baseline: bool) -> str:
    def fmt(value: Any) -> str:
        return "%.2f" % value if value is not None else "—"

    lines = ["# Cgame stress: prioritized bottlenecks", "",
             "Failures > matched-run regressions > frame pacing > RAM caps > CPU intensity.",
             "Baseline: %s. Match workload, hardware, build settings, GPU and power profile."
             % ("provided" if has_baseline else "none (regressions cannot be assessed)"),
             "CPU core equivalents = child CPU seconds / wall seconds; not CPU utilization %.",
             "Frame p95 is max of each run's frame-interval p95; not GPU time or pooled p95.",
             "Different scenarios perform different amounts of work: absolute times are NOT comparable throughput.",
             "",
             "| Case | Status | Wall s | Engine ms | Frame p95 ms | RSS MiB | Δ engine % | Findings |",
             "| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |"]
    for r in rows:
        lines.append("| %s | %s | %s | %s | %s | %s | %s | %s |" % (
            r["case"], r["status"], fmt(r["wall_s"]), fmt(r["engine_ms"]),
            fmt(r["frame_p95_ms"]), fmt(r["peak_rss_mib"]),
            fmt(r["engine_delta_pct"]), r["findings"].replace("|", "\\|")))
    lines.extend(["", "Investigate failures first. Then use CPU, heap or native GPU profilers",
                  "on matching scenarios to confirm causes. Thresholds only indicate suspects.", ""])
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path)
    parser.add_argument("--baseline", type=Path)
    parser.add_argument("--markdown", type=Path)
    parser.add_argument("--csv", type=Path)
    parser.add_argument("--max-regression-pct", type=float, default=20.0)
    parser.add_argument("--max-frame-p95-ms", type=float, default=33.3)
    parser.add_argument("--max-rss-mib", type=float, default=2048.0)
    parser.add_argument("--fail-on-findings", action="store_true")
    args = parser.parse_args(argv)
    if any(not math.isfinite(v) or v <= 0 for v in (
            args.max_regression_pct, args.max_frame_p95_ms, args.max_rss_mib)):
        parser.error("All thresholds must be finite positive numbers")
    try:
        report = json.loads(args.report.read_text(encoding="utf-8"))
        baseline = (json.loads(args.baseline.read_text(encoding="utf-8"))
                    if args.baseline else None)
        rows = analyze(report, baseline, regression_pct=args.max_regression_pct,
                       frame_limit_ms=args.max_frame_p95_ms, rss_limit_mib=args.max_rss_mib)
    except (OSError, ValueError, TypeError, KeyError) as exc:
        parser.error(str(exc))
    markdown = as_markdown(rows, baseline is not None)
    for destination, content in ((args.markdown, markdown), (args.csv, as_csv(rows))):
        if destination:
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_text(content, encoding="utf-8")
    print(markdown)
    return int(args.fail_on_findings and any(row["priority"] >= 40 for row in rows))


if __name__ == "__main__":
    raise SystemExit(main())
