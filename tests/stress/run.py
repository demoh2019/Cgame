#!/usr/bin/env python3
"""Run deterministic Cgame/Godot stress cases in isolated, resource-limited processes.

Only standard-library dependencies are required (psutil optionally enables RSS
sampling on macOS/Windows). Brutal workloads are opt-in and never used by CI.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import math
import os
from pathlib import Path
import platform
import statistics
import subprocess
import sys
import tempfile
import time
from typing import Any

PREFIX = "STRESS_RESULT:"
CASES = (
    "containers", "strings", "script_vm", "math", "signals",
    "scene_tree", "packed_scene", "images", "json", "stream",
    "file_io", "threads", "physics_2d", "physics_3d",
    "memory_churn", "render_2d", "render_3d",
)
RENDER_CASES = frozenset(("render_2d", "render_3d"))
# Each scenario runs in a fresh process. No preset has unlimited RSS or wall time.
PRESETS = {
    "smoke": dict(scale=1, frames=12, repeats=1, timeout=90.0, rss_mib=2048),
    "standard": dict(scale=4, frames=90, repeats=3, timeout=240.0, rss_mib=4096),
    "soak": dict(scale=12, frames=600, repeats=5, timeout=900.0, rss_mib=6144),
    "brutal": dict(scale=50, frames=3600, repeats=10, timeout=1800.0, rss_mib=8192),
}


def rss_mib(pid: int) -> float | None:
    """Resident memory, not virtual size, for the child process."""
    try:
        import psutil  # type: ignore[import-not-found]

        return psutil.Process(pid).memory_info().rss / 1048576.0
    except (ImportError, OSError):
        pass
    try:
        # Linux VmRSS is in KiB. Missing on other platforms.
        for line in Path("/proc/%d/status" % pid).read_text().splitlines():
            if line.startswith("VmRSS:"):
                return int(line.split()[1]) / 1024.0
    except (OSError, ValueError, IndexError):
        pass
    return None


def cpu_seconds(pid: int) -> float | None:
    """CPU user+system seconds, sampled while the child is alive."""
    try:
        import psutil  # type: ignore[import-not-found]

        times = psutil.Process(pid).cpu_times()
        return times.user + times.system
    except (ImportError, OSError):
        pass
    try:
        # Linux stat's comm field may contain spaces or parentheses.
        raw = Path("/proc/%d/stat" % pid).read_text()
        fields = raw.rsplit(")", 1)[1].split()
        return (int(fields[11]) + int(fields[12])) / os.sysconf("SC_CLK_TCK")
    except (OSError, ValueError, IndexError, AttributeError):
        return None


def parse_result(log: str, case: str, scale: int, frames: int, seed: int) -> dict[str, Any]:
    markers = [line[len(PREFIX):] for line in log.splitlines() if line.startswith(PREFIX)]
    if len(markers) != 1:
        raise ValueError("Expected exactly one STRESS_RESULT marker, got %d" % len(markers))
    data = json.loads(markers[0])
    if not isinstance(data, dict):
        raise ValueError("Stress result must be an object")
    for key, expected in (("case", case), ("scale", scale), ("frames", frames), ("seed", seed)):
        if data.get(key) != expected:
            raise ValueError("Wrong %s in Godot result: %r != %r" % (key, data.get(key), expected))
    if not isinstance(data.get("duration_ms"), (int, float)) or not math.isfinite(data["duration_ms"]):
        raise ValueError("Invalid engine duration")
    if data["duration_ms"] < 0:
        raise ValueError("Negative engine duration")
    detail = data.get("detail")
    if not isinstance(detail, dict) or "error" in detail:
        raise ValueError("Engine scenario failed: %r" % detail)
    return data


def choose_cases(requested: list[str], render_mode: str) -> list[str]:
    cases = []
    names = requested or ["all"]
    for item in names:
        for name in item.split(","):
            name = name.strip()
            expanded = [c for c in CASES if render_mode == "display" or c not in RENDER_CASES] if name == "all" else [name]
            for candidate in expanded:
                if candidate not in CASES:
                    raise ValueError("Unknown stress case: %s" % candidate)
                if candidate in RENDER_CASES and render_mode != "display":
                    raise ValueError("%s requires --render-mode display; --headless measures a dummy renderer" % candidate)
                if candidate not in cases:
                    cases.append(candidate)
    return cases


def build_command(binary: str, project: Path, case: str, scale: int, frames: int,
                  seed: int, render_mode: str, extra_args: list[str]) -> list[str]:
    cmd = [binary]
    if render_mode == "headless":
        cmd.append("--headless")
    cmd += ["--path", str(project), "--script", "res://stress.gd", "--no-header"]
    cmd += extra_args
    cmd += ["--", "--case=" + case, "--scale=" + str(scale), "--frames=" + str(frames),
            "--seed=" + str(seed)]
    return cmd


def run_once(cmd: list[str], timeout: float, rss_limit_mib: float,
             case: str, scale: int, frames: int, seed: int) -> dict[str, Any]:
    start = time.monotonic()
    maximum_rss: float | None = None
    latest_cpu: float | None = None
    failure = None
    # A file, rather than a PIPE, avoids deadlock if the engine emits megabytes of errors.
    with tempfile.TemporaryFile(mode="w+t", encoding="utf-8", errors="replace") as output:
        try:
            process = subprocess.Popen(cmd, stdout=output, stderr=subprocess.STDOUT)
        except OSError as exc:
            return {"status": "failed", "failure": "launch: %s" % exc,
                    "wall_seconds": 0.0, "peak_rss_mib": None, "exit_code": None}
        while process.poll() is None:
            elapsed = time.monotonic() - start
            current_rss = rss_mib(process.pid)
            current_cpu = cpu_seconds(process.pid)
            if current_cpu is not None:
                latest_cpu = current_cpu
            if current_rss is not None:
                maximum_rss = max(maximum_rss or 0.0, current_rss)
                if current_rss > rss_limit_mib:
                    failure = "rss_limit_exceeded"
            if elapsed > timeout:
                failure = "timeout"
            if failure is not None:
                process.kill()
                break
            time.sleep(0.05)
        process.wait()
        elapsed = time.monotonic() - start
        output.seek(0)
        log = output.read()
    result: dict[str, Any] = {
        "status": "passed",
        "wall_seconds": round(elapsed, 6),
        "peak_rss_mib": round(maximum_rss, 3) if maximum_rss is not None else None,
        "cpu_seconds": round(latest_cpu, 6) if latest_cpu is not None else None,
        "exit_code": process.returncode,
    }
    if failure is None and process.returncode != 0:
        failure = "engine_exit_%d" % process.returncode
    if failure is None:
        try:
            result["engine"] = parse_result(log, case, scale, frames, seed)
        except (ValueError, json.JSONDecodeError) as exc:
            failure = "invalid_result: %s" % exc
    if failure is not None:
        result["status"] = "failed"
        result["failure"] = failure
        result["log_tail"] = log[-12000:]
    return result


def summarize(runs: list[dict[str, Any]]) -> dict[str, Any]:
    passed = [r for r in runs if r["status"] == "passed"]
    wall = sorted(r["wall_seconds"] for r in passed)
    memories = [r["peak_rss_mib"] for r in runs if r["peak_rss_mib"] is not None]
    cpu_times = [r["cpu_seconds"] for r in passed if r.get("cpu_seconds") is not None]
    return {
        "status": "passed" if len(passed) == len(runs) else "failed",
        "median_wall_seconds": round(statistics.median(wall), 6) if wall else None,
        "p95_wall_seconds": round(wall[math.ceil(0.95 * len(wall)) - 1], 6) if wall else None,
        "max_rss_mib": round(max(memories), 3) if memories else None,
        "median_cpu_seconds": round(statistics.median(cpu_times), 6) if cpu_times else None,
        "runs": runs,
    }


def compare_baseline(current: dict[str, Any], baseline: dict[str, Any],
                     percent: float, memory_growth_limit_mib: float | None) -> list[str]:
    errors: list[str] = []
    keys = ("preset", "scale", "frames", "render_mode")
    for key in keys:
        if current.get("configuration", {}).get(key) != baseline.get("configuration", {}).get(key):
            raise ValueError("Baseline configuration mismatch: %s" % key)
    for name, data in current["cases"].items():
        previous = baseline.get("cases", {}).get(name)
        if not previous or data["status"] != "passed":
            continue
        for field in ("median_wall_seconds", "median_cpu_seconds", "max_rss_mib"):
            new, old = data.get(field), previous.get(field)
            if new is not None and old is not None and old > 0 and new > old * (1 + percent / 100.0):
                errors.append("%s %s: %.3f > %.3f (baseline + %.1f%%)" %
                              (name, field, new, old, percent))
    if memory_growth_limit_mib is not None and "memory_churn" in current["cases"]:
        for run in current["cases"]["memory_churn"]["runs"]:
            if run["status"] != "passed":
                continue
            growth = run["engine"]["detail"]["retained_growth_bytes"] / 1048576.0
            if growth > memory_growth_limit_mib:
                errors.append("memory_churn retained growth %.3f MiB > %.3f MiB" %
                              (growth, memory_growth_limit_mib))
    return errors


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN", "./bin/godot.linuxbsd.editor.dev.x86_64"))
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parent)
    parser.add_argument("--preset", choices=PRESETS, default="smoke")
    parser.add_argument("--case", action="append", default=[], help="Repeat or use a comma-separated list; default: all")
    parser.add_argument("--render-mode", choices=("headless", "display"), default="headless")
    parser.add_argument("--repeats", type=int)
    parser.add_argument("--scale", type=int)
    parser.add_argument("--frames", type=int)
    parser.add_argument("--timeout", type=float, help="Seconds per scenario process")
    parser.add_argument("--rss-limit-mib", type=float, help="Kill scenario when resident memory passes this limit")
    parser.add_argument("--seed", type=int, default=12345)
    parser.add_argument("--godot-arg", action="append", default=[], help="Extra Godot argument before --")
    parser.add_argument("--baseline", type=Path, help="Previous JSON report with identical preset/scale/mode")
    parser.add_argument("--max-regression-pct", type=float, default=20.0)
    parser.add_argument("--max-retained-growth-mib", type=float, default=None)
    parser.add_argument("--output", type=Path, default=Path("stress-results.json"))
    parser.add_argument("--list-cases", action="store_true")
    args = parser.parse_args(argv)

    if args.list_cases:
        print("\n".join(CASES))
        return 0
    config = dict(PRESETS[args.preset])
    for key, value in (("repeats", args.repeats), ("scale", args.scale),
                       ("frames", args.frames), ("timeout", args.timeout),
                       ("rss_mib", args.rss_limit_mib)):
        if value is not None:
            config[key] = value
    if (config["repeats"] < 1 or config["scale"] < 1 or config["scale"] > 1000
            or config["frames"] < 1 or config["frames"] > 100000
            or config["timeout"] <= 0 or config["rss_mib"] <= 0
            or args.max_regression_pct < 0
            or (args.max_retained_growth_mib is not None and args.max_retained_growth_mib < 0)):
        parser.error("All limits and iterations must be positive and within engine bounds")
    try:
        selected = choose_cases(args.case, args.render_mode)
    except ValueError as exc:
        parser.error(str(exc))

    project = args.project.resolve()
    binary = str(Path(args.godot).resolve()) if ("/" in args.godot or "\\" in args.godot) else args.godot
    if not (project / "project.godot").is_file() or not (project / "stress.gd").is_file():
        parser.error("Invalid stress project: %s" % project)
    report: dict[str, Any] = {
        "schema_version": 1,
        "created_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "host": {"platform": platform.platform(), "processor": platform.processor(),
                 "logical_cpus": os.cpu_count()},
        "godot_binary": binary,
        "configuration": {"preset": args.preset, "scale": config["scale"],
                          "frames": config["frames"], "repeats": config["repeats"],
                          "render_mode": args.render_mode, "timeout_seconds": config["timeout"],
                          "rss_limit_mib": config["rss_mib"], "seed": args.seed},
        "cases": {},
        "failures": [],
    }
    for case in selected:
        runs = []
        for repetition in range(config["repeats"]):
            cmd = build_command(binary, project, case, config["scale"], config["frames"],
                                args.seed, args.render_mode, args.godot_arg)
            print("[%s] %s run %d/%d" % (args.preset, case, repetition + 1, config["repeats"]), flush=True)
            run = run_once(cmd, config["timeout"], config["rss_mib"],
                           case, config["scale"], config["frames"], args.seed)
            runs.append(run)
            print("  %s: %.3fs; RSS %s MiB" % (
                run["status"], run["wall_seconds"], run["peak_rss_mib"]), flush=True)
            if run["status"] != "passed":
                report["failures"].append("%s #%d: %s" %
                                          (case, repetition + 1, run.get("failure", "failed")))
        report["cases"][case] = summarize(runs)

    try:
        baseline = json.loads(args.baseline.read_text(encoding="utf-8")) if args.baseline else report
        report["failures"].extend(compare_baseline(report, baseline,
                              args.max_regression_pct, args.max_retained_growth_mib))
    except (ValueError, OSError, KeyError, TypeError) as exc:
        report["failures"].append("baseline_error: %s" % exc)
    report["status"] = "failed" if report["failures"] else "passed"
    args.output.parent.mkdir(parents=True, exist_ok=True)
    temp = args.output.with_name(args.output.name + ".tmp")
    temp.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    temp.replace(args.output)
    print("Stress report: %s (%s)" % (args.output, report["status"]))
    for error in report["failures"]:
        print("FAIL: " + error, file=sys.stderr)
    return 1 if report["failures"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
