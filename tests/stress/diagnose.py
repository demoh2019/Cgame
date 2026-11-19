#!/usr/bin/env python3
"""Analyze Cgame stress JSON without mistaking unlike workloads for benchmarks."""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any


def finite(value: Any) -> float | None:
    """Accept numeric measurements but not booleans, NaN, or infinity."""
    if isinstance(value, bool) or not isinstance(value, (float, int)):
        return None
    result = float(value)
    return result if math.isfinite(result) else None


def observed_spike(case: dict[str, Any]) -> float | None:
    values = []
    for run in case.get("runs", []):
        if run.get("status") != "passed":
            continue
        detail = run.get("engine", {}).get("detail", {})
        if not isinstance(detail, dict):
            continue
        for name in ("peak_frame_ms", "peak_physics_ms", "peak_process_ms"):
            value = finite(detail.get(name))
            if value is not None:
                values.append(value)
    return max(values) if values else None


def delta_percent(current: float | None, old: float | None) -> float | None:
    if current is None or old is None or old <= 0:
        return None
    return (current / old - 1.0) * 100.0


def compatible(report: dict[str, Any], baseline: dict[str, Any]) -> None:
    """Reject known incompatible experiment settings; hardware still matters."""
    for field in ("preset", "scale", "frames", "render_mode", "seed"):
        left = report.get("configuration", {}).get(field)
        right = baseline.get("configuration", {}).get(field)
        if left != right:
            raise ValueError("Baseline configuration mismatch: " + field)


def _table(headers: tuple[str, ...], rows: list[tuple[str, ...]]) -> list[str]:
    return ["| " + " | ".join(headers) + " |",
            "| " + " | ".join("---" for _ in headers) + " |"] + [
                "| " + " | ".join(cell.replace("|", "\\\\|") for cell in row) + " |"
                for row in rows
            ]


def build_report(report: dict[str, Any], baseline: dict[str, Any] | None = None,
                 top: int = 15) -> str:
    if top <= 0:
        raise ValueError("top must be positive")
    cases = report.get("cases", {})
    if not isinstance(cases, dict):
        raise ValueError("Invalid stress report: cases must be an object")
    lines = ["# Cgame stress bottleneck diagnosis", "",
             "Status: **%s**; scenarios: **%d**." % (report.get("status", "unknown"), len(cases)),
             "", "Rankings are **within the same measured run**. Different scenarios perform",
             "different amounts of work: raw timings do not imply relative subsystem efficiency.",
             ""]
    failures = report.get("failures", [])
    if failures:
        lines.extend(["## Failures", ""])
        lines.extend("- " + str(failure) for failure in failures)
        lines.append("")

    def ranking(title: str, metric: str, unit: str, descending: bool = True) -> None:
        entries = [(name, finite(data.get(metric)))
                   for name, data in cases.items() if isinstance(data, dict)]
        entries = [(name, value) for name, value in entries if value is not None]
        entries.sort(key=lambda item: item[1], reverse=descending)
        lines.extend(["## " + title, ""])
        if not entries:
            lines.extend(["No measurements available.", ""])
            return
        lines.extend(_table(("Scenario", unit), [
            (name, "%.3f" % value) for name, value in entries[:top]
        ]))
        lines.append("")

    ranking("Slowest scenarios by median engine time", "median_engine_ms", "ms")
    ranking("Slowest scenarios by process wall time", "median_wall_seconds", "seconds")
    ranking("Largest resident-memory footprints", "max_rss_mib", "MiB")
    spikes = [(name, observed_spike(data)) for name, data in cases.items()
              if isinstance(data, dict)]
    spikes = sorted(((name, value) for name, value in spikes if value is not None),
                    key=lambda item: item[1], reverse=True)
    lines.extend(["## Worst observed per-frame spikes", ""])
    if spikes:
        lines.extend(_table(("Scenario", "Peak frame/physics ms"), [
            (name, "%.3f" % ms) for name, ms in spikes[:top]
        ]))
    else:
        lines.append("No frame-timing measurements available.")
    lines.append("")

    if baseline is not None:
        compatible(report, baseline)
        lines.extend(["## Changes relative to baseline", "",
                      "Only overlapping scenarios with numeric measurements are compared.", ""])
        changes = []
        for name, data in cases.items():
            if not isinstance(data, dict):
                continue
            previous = baseline.get("cases", {}).get(name)
            if not isinstance(previous, dict):
                continue
            for metric, unit in (("median_engine_ms", "engine ms"),
                                 ("median_wall_seconds", "wall s"),
                                 ("max_rss_mib", "RSS MiB")):
                new, old = finite(data.get(metric)), finite(previous.get(metric))
                change = delta_percent(new, old)
                if change is not None:
                    changes.append((name, unit, old, new, change))
        changes.sort(key=lambda item: item[-1], reverse=True)
        if changes:
            lines.extend(_table(("Scenario", "Metric", "Baseline", "Current", "Change"), [
                (name, unit, "%.3f" % old, "%.3f" % new, "%+.1f%%" % change)
                for name, unit, old, new, change in changes[:top]
            ]))
        else:
            lines.append("No comparable measurements.")
        lines.append("")
    lines.extend(["## Follow-up", "",
                  "Profile the top reproducible regression on the **same host** with CPU",
                  "sampling, heap profiling or GPU capture. Record compiler flags, hardware,",
                  "rendering driver, thermal state and repeat count. Peak RSS and engine",
                  "static allocation statistics are different measures.", ""])
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path)
    parser.add_argument("--baseline", type=Path)
    parser.add_argument("--top", type=int, default=15)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    try:
        report = json.loads(args.report.read_text(encoding="utf-8"))
        baseline = json.loads(args.baseline.read_text(encoding="utf-8")) if args.baseline else None
        rendered = build_report(report, baseline, args.top)
    except (OSError, ValueError, TypeError, KeyError) as exc:
        parser.error(str(exc))
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(rendered, encoding="utf-8")
        print(args.output)
    else:
        print(rendered)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
