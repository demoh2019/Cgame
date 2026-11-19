#!/usr/bin/env python3
"""Opt-in multi-scale Cgame stress sweep to expose nonlinear engine-time and RSS growth.

Use on an isolated machine; never compare separate hardware or rendering modes.
Runs each point in a fresh Godot process through run.py's existing watchdog.
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


def parse_scales(raw: str) -> list[int]:
    try:
        scales = [int(part.strip()) for part in raw.split(",")]
    except ValueError as exc:
        raise argparse.ArgumentTypeError("Scales must be comma-separated integers") from exc
    if len(scales) < 2 or len(scales) > 12 or any(n < 1 or n > 1000 for n in scales):
        raise argparse.ArgumentTypeError("Provide 2..12 scales, each in 1..1000")
    if scales != sorted(set(scales)):
        raise argparse.ArgumentTypeError("Scales must be strictly increasing and unique")
    return scales


def analyze_scaling(samples: list[dict[str, Any]], threshold: float = 1.25) -> dict[str, Any]:
    """Diagnostic, not a proof of algorithmic complexity or a memory leak."""
    if len(samples) < 2:
        raise ValueError("Scaling requires at least two samples")
    if any(s.get("status") != "passed" for s in samples):
        return {"status": "failed", "signals": ["workload failure"]}
    first, last = samples[0], samples[-1]
    x0, x1 = first["scale"], last["scale"]
    if x0 >= x1 or any(a["scale"] >= b["scale"] for a, b in zip(samples, samples[1:])):
        raise ValueError("Samples must be ordered by ascending scale")

    t0, t1 = first.get("median_engine_ms"), last.get("median_engine_ms")
    exponent = None
    growth = None
    if t0 is not None and t1 is not None and t0 > 0 and t1 > 0:
        growth = t1 / t0
        exponent = math.log(growth) / math.log(x1 / x0)
    variable = any(
        s.get("median_engine_ms") is not None
        and s.get("p95_engine_ms") is not None
        and s["median_engine_ms"] > 0
        and s["p95_engine_ms"] / s["median_engine_ms"] > 1.5
        for s in samples
    )
    signals = []
    if variable:
        signals.append("high timing variance")
    # A very short baseline is dominated by noise and process scheduling.
    if exponent is not None and t0 >= 5 and t1 >= 2 * t0 and exponent >= threshold:
        if variable:
            signals.append("possible nonlinear time growth (noisy)")
        else:
            signals.append("possible nonlinear time growth")

    rss = [(s["scale"], s.get("median_rss_mib")) for s in samples]
    rss_delta = None
    if rss[0][1] is not None and rss[-1][1] is not None:
        rss_delta = round(rss[-1][1] - rss[0][1], 3)
    rates = []
    for (left_x, left_y), (right_x, right_y) in zip(rss, rss[1:]):
        if left_y is not None and right_y is not None:
            rates.append((right_y - left_y) / (right_x - left_x))
    if len(rates) >= 2 and rss_delta is not None and rss_delta >= 64:
        if rates[0] > 1 and rates[-1] > 1.5 * rates[0]:
            signals.append("accelerating RSS growth (investigate allocations)")

    return {
        "status": "investigate" if signals else "ok",
        "engine_time_growth_factor": round(growth, 4) if growth is not None else None,
        "engine_time_exponent": round(exponent, 4) if exponent is not None else None,
        "rss_growth_mib": rss_delta,
        "signals": signals,
    }


def summarize_scale(runs: list[dict[str, Any]], scale: int) -> dict[str, Any]:
    summary = stress.summarize(runs)
    passed = [r for r in runs if r.get("status") == "passed"]
    rss_values = [r["peak_rss_mib"] for r in passed if r.get("peak_rss_mib") is not None]
    return {
        "scale": scale,
        "status": summary["status"],
        "median_engine_ms": summary["median_engine_ms"],
        "p95_engine_ms": summary["p95_engine_ms"],
        "median_wall_seconds": summary["median_wall_seconds"],
        "median_rss_mib": round(statistics.median(rss_values), 3) if rss_values else None,
        "max_rss_mib": summary["max_rss_mib"],
        "runs": runs,
    }


def markdown_report(report: dict[str, Any]) -> str:
    records = []
    for case, record in report["cases"].items():
        analysis = record["analysis"]
        exponent = analysis["engine_time_exponent"]
        records.append((case, exponent, analysis["rss_growth_mib"], "; ".join(analysis["signals"])))
    records.sort(key=lambda row: row[1] if row[1] is not None else float("-inf"), reverse=True)

    def fmt(value: Any) -> str:
        return "%.3f" % value if value is not None else "n/a"

    lines = [
        "# Cgame stress scale sweep",
        "",
        "Scales: %s; frames: %s; repeats: %s; mode: %s." % (
            ",".join(map(str, report["configuration"]["scales"])),
            report["configuration"]["frames"], report["configuration"]["repeats"],
            report["configuration"]["render_mode"]),
        "",
        "Engine-time exponent is inferred from the **first and last scales**: "
        "1.0 approximates linear growth, above 1.0 suggests superlinear growth. "
        "Signals are heuristics, not complexity proofs or leak diagnoses.",
        "",
        "| Case | Engine-time exponent | RSS change (MiB) | Signals |",
        "| --- | ---: | ---: | --- |",
    ]
    for name, exponent, rss, signals in records:
        lines.append("| %s | %s | %s | %s |" % (name, fmt(exponent), fmt(rss), signals or "—"))
    lines.append("")
    lines.append("Failures: %d" % len(report["failures"]))
    lines.extend("- %s" % str(f).replace("\n", " ") for f in report["failures"])
    lines.append("")
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN", "./bin/godot.linuxbsd.editor.dev.x86_64"))
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parent)
    parser.add_argument("--scales", type=parse_scales, default=parse_scales("1,2,4,8"))
    parser.add_argument("--case", action="append", default=[], help="Case list or 'all' (render requires display)")
    parser.add_argument("--frames", type=int, default=30)
    parser.add_argument("--repeats", type=int, default=3)
    parser.add_argument("--timeout", type=float, default=240.0)
    parser.add_argument("--rss-limit-mib", type=float, default=4096.0)
    parser.add_argument("--render-mode", choices=("headless", "display"), default="headless")
    parser.add_argument("--seed", type=int, default=12345)
    parser.add_argument("--nonlinear-exponent", type=float, default=1.25)
    parser.add_argument("--output", type=Path, default=Path("stress-scale-sweep.json"))
    parser.add_argument("--summary-md", type=Path)
    args = parser.parse_args(argv)

    if args.frames < 1 or args.frames > 100000 or args.repeats < 1 or args.repeats > 100:
        parser.error("Invalid frame count or repeats")
    if args.timeout <= 0 or args.rss_limit_mib <= 0 or not (1 < args.nonlinear_exponent < 5):
        parser.error("Timeout, RSS cap and exponent must be within supported bounds")
    try:
        cases = stress.choose_cases(args.case, args.render_mode)
    except ValueError as exc:
        parser.error(str(exc))
    project = args.project.resolve()
    if not (project / "project.godot").is_file():
        parser.error("Missing project.godot")
    binary = str(Path(args.godot).resolve()) if ("/" in args.godot or "\\" in args.godot) else args.godot
    report: dict[str, Any] = {
        "schema_version": 2,
        "created_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "configuration": {
            "scales": args.scales, "frames": args.frames, "repeats": args.repeats,
            "render_mode": args.render_mode, "rss_scope": "process_tree",
            "seed": args.seed, "timeout_seconds": args.timeout,
            "rss_limit_mib": args.rss_limit_mib, "nonlinear_exponent": args.nonlinear_exponent,
        },
        "cases": {},
        "failures": [],
    }
    for case in cases:
        points = []
        for scale in args.scales:
            runs = []
            for repetition in range(args.repeats):
                print("[%s] scale %s, run %d/%d" % (case, scale, repetition + 1, args.repeats), flush=True)
                cmd = stress.build_command(binary, project, case, scale, args.frames, args.seed, args.render_mode, [])
                result = stress.run_once(cmd, args.timeout, args.rss_limit_mib, case, scale, args.frames, args.seed)
                runs.append(result)
                if result["status"] != "passed":
                    report["failures"].append("%s scale %d run %d: %s" % (
                        case, scale, repetition + 1, result.get("failure")))
            points.append(summarize_scale(runs, scale))
        report["cases"][case] = {
            "scales": points,
            "analysis": analyze_scaling(points, args.nonlinear_exponent),
        }
    report["status"] = "failed" if report["failures"] else "passed"
    args.output.parent.mkdir(parents=True, exist_ok=True)
    temporary = args.output.with_suffix(args.output.suffix + ".tmp")
    temporary.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    temporary.replace(args.output)
    if args.summary_md is not None:
        args.summary_md.parent.mkdir(parents=True, exist_ok=True)
        args.summary_md.write_text(markdown_report(report), encoding="utf-8")
    for failure in report["failures"]:
        print("FAIL: " + failure, file=sys.stderr)
    print("Scale sweep: %s (%s)" % (args.output, report["status"]))
    return 1 if report["failures"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
