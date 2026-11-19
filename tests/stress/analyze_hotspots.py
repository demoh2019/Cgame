#!/usr/bin/env python3
"""Compare Cgame stress reports and rank reproducible performance regressions.

Supports both standard run.py and run_gpu.py JSON report formats.
No external dependencies. Baseline comparisons require matching workload settings.
"""
from __future__ import annotations

import argparse
import csv
import io
import json
import math
from pathlib import Path
import statistics
from typing import Any

# Increasing these measurements can indicate a performance regression. Workload
# volumes differ between *cases*, so only compare the same case and configuration.
METRICS = (
    ("median_engine_ms", "Engine time", "ms"),
    ("median_wall_seconds", "Wall time", "s"),
    ("median_cpu_seconds", "CPU time", "s"),
    ("max_rss_mib", "Peak RSS", "MiB"),
    ("median_frame_p95_ms", "Frame latency p95", "ms"),
)


def numeric(value: Any) -> float | None:
    if isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value):
        return float(value)
    return None


def case_metrics(case: dict[str, Any]) -> dict[str, float | None]:
    """Normalize optional raw-run engine timing and frame latency measurements."""
    result = {key: numeric(case.get(key)) for key, _, _ in METRICS}
    runs = [r for r in case.get("runs", []) if r.get("status") == "passed"]
    if result["median_engine_ms"] is None:
        engine = [numeric(r.get("engine", {}).get("duration_ms")) for r in runs]
        valid = [n for n in engine if n is not None]
        result["median_engine_ms"] = statistics.median(valid) if valid else None
    if result["median_frame_p95_ms"] is None:
        latency = [
            numeric(r.get("engine", {}).get("detail", {}).get("frame_p95_ms"))
            for r in runs
        ]
        valid = [n for n in latency if n is not None]
        result["median_frame_p95_ms"] = statistics.median(valid) if valid else None
    return result


def validate_baseline(current: dict[str, Any], baseline: dict[str, Any]) -> None:
    """Refuse demonstrably incomparable run settings; GPU model remains external."""
    for key in ("preset", "scale", "frames", "render_mode"):
        a, b = current.get("configuration", {}).get(key), baseline.get("configuration", {}).get(key)
        if a != b:
            raise ValueError("Mismatched workload configuration %s: %r vs %r" % (key, a, b))
    for key in ("platform", "processor", "logical_cpus"):
        a, b = current.get("host", {}).get(key), baseline.get("host", {}).get(key)
        if a is not None and b is not None and a != b:
            raise ValueError("Different host %s: %r vs %r" % (key, a, b))


def analyze(current: dict[str, Any], baseline: dict[str, Any] | None = None,
            leak_warning_mib: float = 64.0) -> dict[str, Any]:
    """Return ranked regressions, expensive scenarios and memory-retention signals."""
    if baseline is not None:
        validate_baseline(current, baseline)
    cases = current.get("cases", {})
    regressions: list[dict[str, Any]] = []
    expensive: list[dict[str, Any]] = []
    memory_signals: list[dict[str, Any]] = []
    failures = list(current.get("failures", []))
    for name, data in cases.items():
        if data.get("status") != "passed":
            failures.append("%s: scenario not passed" % name)
            continue
        observed = case_metrics(data)
        engine = observed["median_engine_ms"]
        if engine is not None:
            expensive.append({"case": name, "engine_ms": round(engine, 3),
                              "wall_s": observed["median_wall_seconds"],
                              "rss_mib": observed["max_rss_mib"],
                              "frame_p95_ms": observed["median_frame_p95_ms"]})
        if baseline:
            previous = baseline.get("cases", {}).get(name)
            if previous is None or previous.get("status") != "passed":
                continue
            expected = case_metrics(previous)
            for key, label, unit in METRICS:
                new, old = observed[key], expected[key]
                if new is None or old is None or old <= 0:
                    continue
                change = (new / old - 1.0) * 100.0
                if change <= 0:
                    continue
                samples = min(
                    sum(r.get("status") == "passed" for r in data.get("runs", [])),
                    sum(r.get("status") == "passed" for r in previous.get("runs", [])),
                )
                regressions.append({
                    "case": name, "metric": key, "description": label, "unit": unit,
                    "current": round(new, 6), "baseline": round(old, 6),
                    "increase_pct": round(change, 3),
                    "sample_repeats": samples,
                    "low_confidence": samples < 3,
                })
        if name == "memory_churn":
            for number, item in enumerate(data.get("runs", []), start=1):
                if item.get("status") != "passed":
                    continue
                detail = item.get("engine", {}).get("detail", {})
                retained = numeric(detail.get("retained_growth_bytes"))
                if retained is not None and retained > leak_warning_mib * 1048576:
                    memory_signals.append({
                        "case": name, "run": number,
                        "retained_growth_mib": round(retained / 1048576, 3),
                        "note": "Allocator-retention heuristic, NOT proof of a memory leak",
                    })
    regressions.sort(key=lambda row: row["increase_pct"], reverse=True)
    expensive.sort(key=lambda row: row["engine_ms"], reverse=True)
    return {
        "schema_version": 1,
        "current_status": current.get("status"),
        "baseline_compared": baseline is not None,
        "configuration": current.get("configuration", {}),
        "failures": failures,
        "regressions": regressions,
        "expensive_workloads": expensive,
        "memory_signals": memory_signals,
    }


def markdown(result: dict[str, Any]) -> str:
    lines = ["# Cgame performance hotspot analysis", "",
             "**Comparison:** %s" % ("matched baseline" if result["baseline_compared"]
                                     else "single report; no baseline"), "",
             "## Regressions (same case only)", ""]
    if result["baseline_compared"]:
        lines.extend(["| Case | Metric | Current | Baseline | Change | Repeats |",
                      "| --- | --- | ---: | ---: | ---: | ---: |"])
        for row in result["regressions"]:
            quality = " (low confidence)" if row["low_confidence"] else ""
            lines.append("| %s | %s | %.3f %s | %.3f %s | +%.2f%% | %d%s |" %
                         (row["case"], row["description"], row["current"], row["unit"],
                          row["baseline"], row["unit"], row["increase_pct"],
                          row["sample_repeats"], quality))
        if not result["regressions"]:
            lines.append("| — | No observed increases | — | — | — | — |")
    else:
        lines.append("A baseline is required to identify regressions. "
                     "Absolute runtimes across unrelated workloads are not comparable.")
    lines.extend(["", "## Most expensive measured workloads", "",
                  "| Case | Engine (ms) | Wall (s) | RSS (MiB) | Frame p95 (ms) |",
                  "| --- | ---: | ---: | ---: | ---: |"])
    def fmt(number: float | None) -> str:
        return "—" if number is None else "%.3f" % number
    for row in result["expensive_workloads"]:
        lines.append("| %s | %s | %s | %s | %s |" %
                     (row["case"], fmt(row["engine_ms"]), fmt(row["wall_s"]),
                      fmt(row["rss_mib"]), fmt(row["frame_p95_ms"])))
    lines.extend(["", "## Memory retention warnings", ""])
    if result["memory_signals"]:
        for row in result["memory_signals"]:
            lines.append("- %s #%d: +%.3f MiB retained (%s)" %
                         (row["case"], row["run"], row["retained_growth_mib"], row["note"]))
    else:
        lines.append("No sampled workload exceeded the configured retention warning threshold.")
    lines.extend(["", "## Failures", ""])
    lines.extend("- " + str(f) for f in result["failures"])
    if not result["failures"]:
        lines.append("No failures recorded.")
    lines.extend(["", "Frame p95 includes frame pacing and synchronization; it is not pure GPU time. "
                  "Headless tests do not measure GPU. Confirm memory leaks with heap profiling. "
                  "A GPU baseline also requires the same model, driver, resolution and VSync.",
                  ""])
    return "\n".join(lines)


def csv_text(result: dict[str, Any]) -> str:
    output = io.StringIO()
    fields = ("case", "metric", "description", "unit", "current",
              "baseline", "increase_pct", "sample_repeats", "low_confidence")
    writer = csv.DictWriter(output, fieldnames=fields)
    writer.writeheader()
    writer.writerows(result["regressions"])
    return output.getvalue()


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("report", type=Path)
    p.add_argument("--baseline", type=Path)
    p.add_argument("--out", type=Path, default=Path("hotspots.json"))
    p.add_argument("--fail-over-pct", type=float,
                   help="Fail on regressions exceeding threshold (requires a baseline)")
    p.add_argument("--min-repeats", type=int, default=3,
                   help="Minimum repeated runs for enforcement, default 3")
    p.add_argument("--leak-warning-mib", type=float, default=64.0)
    args = p.parse_args(argv)
    if args.min_repeats < 1 or args.leak_warning_mib < 0 or (
        args.fail_over_pct is not None and args.fail_over_pct < 0
    ):
        p.error("Invalid thresholds")
    if args.fail_over_pct is not None and args.baseline is None:
        p.error("--fail-over-pct requires --baseline")
    current = json.loads(args.report.read_text(encoding="utf-8"))
    baseline = json.loads(args.baseline.read_text(encoding="utf-8")) if args.baseline else None
    try:
        result = analyze(current, baseline, args.leak_warning_mib)
    except ValueError as exc:
        p.error(str(exc))
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    args.out.with_suffix(".md").write_text(markdown(result), encoding="utf-8")
    args.out.with_suffix(".csv").write_text(csv_text(result), encoding="utf-8")
    failures = [r for r in result["regressions"]
                if args.fail_over_pct is not None and r["increase_pct"] > args.fail_over_pct
                and r["sample_repeats"] >= args.min_repeats]
    print("Hotspot report: %s (%d regressions, %d memory warnings)" %
          (args.out, len(result["regressions"]), len(result["memory_signals"])))
    for item in failures:
        print("REGRESSION: %s %s +%.2f%%" %
              (item["case"], item["metric"], item["increase_pct"]))
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
