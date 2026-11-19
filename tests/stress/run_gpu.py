#!/usr/bin/env python3
"""GPU-specific Cgame stress jobs using the existing watchdog and JSON schema.

A real display is mandatory. Xvfb/Mesa software rendering is *not* a GPU benchmark.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
from pathlib import Path
import platform
import statistics
import sys

import run as core

GPU_CASES = ("texture_upload", "canvas_overdraw", "multimesh_3d",
             "shadow_lights", "cpu_particles", "shader_variants")


def build_gpu_command(binary: str, project: Path, case: str, scale: int,
                      frames: int, seed: int, args: list[str]) -> list[str]:
    if case not in GPU_CASES:
        raise ValueError("Unknown GPU case: " + case)
    return [binary, "--path", str(project), "--script", "res://gpu_stress.gd",
            "--no-header", *args, "--", "--case=" + case, "--scale=" + str(scale),
            "--frames=" + str(frames), "--seed=" + str(seed)]


def frame_summary(runs: list[dict]) -> dict:
    values = [r["engine"]["detail"]["frame_p95_ms"] for r in runs
              if r.get("status") == "passed" and "engine" in r
              and isinstance(r["engine"].get("detail", {}).get("frame_p95_ms"), (int, float))]
    return {"median_frame_p95_ms": round(statistics.median(values), 6) if values else None}


def render_table(report: dict) -> str:
    lines = ["# Cgame display rendering stress", "",
             "Renderer: display, not headless. Identify actual GPU model and driver separately.",
             "", "| Case | Status | Engine ms | Frame p95 ms | Max RSS MiB |",
             "| --- | --- | ---: | ---: | ---: |"]
    for name, values in report["cases"].items():
        def fmt(v):
            return "—" if v is None else "%.3f" % v
        lines.append("| %s | %s | %s | %s | %s |" %
                     (name, values["status"], fmt(values["median_engine_ms"]),
                      fmt(values["median_frame_p95_ms"]), fmt(values["max_rss_mib"])))
    lines.extend(["", "## Failures", ""])
    lines.extend("- " + f for f in report["failures"])
    if not report["failures"]:
        lines.append("No detected failures.")
    lines.extend(["", "Each case has different workload volume. Compare only the same case "
                  "on the same hardware, driver, rendering mode, and resolution.", ""])
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--godot", default=os.environ.get("GODOT_BIN", "./bin/godot.linuxbsd.editor.dev.x86_64"))
    p.add_argument("--project", type=Path, default=Path(__file__).resolve().parent)
    p.add_argument("--preset", choices=core.PRESETS, default="smoke")
    p.add_argument("--case", action="append", choices=GPU_CASES)
    p.add_argument("--scale", type=int)
    p.add_argument("--frames", type=int)
    p.add_argument("--repeats", type=int)
    p.add_argument("--timeout", type=float)
    p.add_argument("--rss-limit-mib", type=float)
    p.add_argument("--seed", type=int, default=12345)
    p.add_argument("--godot-arg", action="append", default=[])
    p.add_argument("--frame-p95-budget-ms", type=float)
    p.add_argument("--output", type=Path, default=Path("gpu-stress.json"))
    args = p.parse_args(argv)
    cfg = dict(core.PRESETS[args.preset])
    for key, val in (("scale", args.scale), ("frames", args.frames),
                     ("repeats", args.repeats), ("timeout", args.timeout),
                     ("rss_mib", args.rss_limit_mib)):
        if val is not None:
            cfg[key] = val
    if (cfg["scale"] < 1 or cfg["scale"] > 1000 or cfg["frames"] < 1
            or cfg["frames"] > 100000 or cfg["repeats"] < 1 or cfg["timeout"] <= 0
            or cfg["rss_mib"] <= 0 or
            (args.frame_p95_budget_ms is not None and args.frame_p95_budget_ms <= 0)):
        p.error("Invalid workload or budget limits")
    if not (args.project / "gpu_stress.gd").is_file():
        p.error("GPU script not found under --project")
    binary = str(Path(args.godot).resolve()) if "/" in args.godot or "\\" in args.godot else args.godot
    cases = args.case or GPU_CASES
    report = {
        "schema_version": 1,
        "created_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "host": {"platform": platform.platform(), "logical_cpus": os.cpu_count()},
        "configuration": {"preset": args.preset, "scale": cfg["scale"],
                          "frames": cfg["frames"], "render_mode": "display",
                          "repeats": cfg["repeats"], "rss_limit_mib": cfg["rss_mib"],
                          "timeout_seconds": cfg["timeout"], "seed": args.seed},
        "cases": {}, "failures": [],
    }
    for case in cases:
        runs = []
        for repeat in range(cfg["repeats"]):
            cmd = build_gpu_command(binary, args.project.resolve(), case, cfg["scale"],
                                    cfg["frames"], args.seed, args.godot_arg)
            print("[%s] %s %d/%d" % (args.preset, case, repeat + 1, cfg["repeats"]), flush=True)
            result = core.run_once(cmd, cfg["timeout"], cfg["rss_mib"], case,
                                   cfg["scale"], cfg["frames"], args.seed)
            runs.append(result)
            if result["status"] != "passed":
                report["failures"].append("%s #%d: %s" %
                                          (case, repeat + 1, result.get("failure", "failed")))
        report["cases"][case] = dict(core.summarize(runs), **frame_summary(runs))
        frame = report["cases"][case]["median_frame_p95_ms"]
        if args.frame_p95_budget_ms is not None and frame is not None and frame > args.frame_p95_budget_ms:
            report["failures"].append("%s p95 frame %.3f > %.3f ms" %
                                      (case, frame, args.frame_p95_budget_ms))
    report["status"] = "failed" if report["failures"] else "passed"
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    args.output.with_suffix(".md").write_text(render_table(report), encoding="utf-8")
    print("GPU report: %s (%s)" % (args.output, report["status"]))
    return 1 if report["failures"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
