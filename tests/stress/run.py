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
import re
import statistics
import subprocess
import sys
import tempfile
import time
from typing import Any

from process_tree import sample as sample_process_tree, isolation_options, kill_group

PREFIX = "STRESS_RESULT:"
# A zero exit status is not enough: the engine can log script/runtime errors.
ENGINE_ERROR = re.compile(r"(?m)^(?:SCRIPT ERROR:|ERROR:|E\s+\d+:)")
CASES = (
    "containers", "array_literals", "dictionary_snapshot", "strings", "script_vm", "math", "signals",
    "scene_tree", "packed_scene", "images", "json", "stream", "stream_bulk",
    "file_io", "threads", "physics_2d", "physics_contacts_zero_friction_2d", "physics_contacts_friction_2d", "physics_contact_manifolds_2d", "physics_contact_block_solver_2d", "physics_3d", "physics_damping_legacy_2d", "physics_damping_implicit_2d", "physics_damping_legacy_3d", "physics_damping_implicit_3d", "physics_box_box_axis_aligned_3d", "physics_box_box_rotated_3d", "physics_box_box_misaligned_3d", "physics_sphere_box_identity_3d", "physics_sphere_box_rotated_3d", "physics_block_solver_sequential_3d", "physics_block_solver_coupled_3d", "physics_frictionless_3d", "physics_soft_contacts_zero_friction_3d", "physics_soft_contacts_friction_3d", "physics_ccd_2d", "physics_separated_pairs_2d", "physics_separated_pairs_3d", "physics_dense_2d", "physics_dense_3d", "physics_pending_3d", "physics_ccd_3d", "physics_joint_chain_2d", "physics_large_island_serial_2d", "physics_large_island_parallel_2d", "physics_multi_island_serial_2d", "physics_multi_island_parallel_2d", "physics_joint_chain_3d", "physics_large_island_3d_serial", "physics_large_island_3d_parallel", "physics_large_island_3d_priority", "physics_large_island_3d_topology_serial", "physics_large_island_3d_topology_parallel", "physics_multi_island_3d_serial", "physics_multi_island_3d_parallel", "physics_multi_island_3d_two_large", "physics_sparse_2d", "physics_sparse_3d", "physics_proxy_same_aabb_2d", "physics_proxy_same_aabb_3d", "physics_proxies_2d", "physics_proxies_3d", "physics_rid_sparse_2d", "physics_rid_sparse_3d", "physics_rid_moving_2d", "physics_rid_moving_3d", "physics_restitution_2d", "physics_restitution_3d",
    "object_churn", "memory_churn", "astar_grid", "astar_grid_neighbors", "astar_grid_jps", "astar_grid_fill", "astar_grid_rebuild", "astar_relax_2d", "astar_relax_3d", "astar_graph", "tweens", "audio_buffers",
    "variant_codec", "packet_stream", "packet_tx_batch", "packet_rx_batch", "packet_variant_reuse", "ui_layout", "grid_reflow", "box_reflow", "flow_reflow", "render_2d", "render_3d", "render_ellipse_2d", "render_light_culling_3d",
    "resource_load",
    "input_map",
    "transform_hierarchy",
    "node_paths", "regex", "compression", "gzip_stream", "hashing",
    "resource_io", "astar_3d", "thread_contention",
    "geometry_2d", "mesh_build", "input_dispatch", "image_codec", "group_calls",
    "packed_arrays", "sorting", "animation_tracks", "physics_raycast_2d", "physics_raycast_3d", "render_multimesh_3d",
    "object_lifecycle", "scene_churn",
    "scene_reparent", "scene_move", "resource_roundtrip", "audio_bus_churn",
    "bitmap_rects", "bitmap_pipeline", "bitmap_morphology",
    "curve_tessellation_2d", "curve_tessellation_3d", "curve_bake", "curve_nearest",
    "canvas_transform_2d", "process_dispatch",
    "physics_filter_toggle_2d", "physics_filter_toggle_3d", "physics_motion_filter_overflow_2d", "physics_motion_filter_overflow_3d", "physics_motion_exclusions_3d", "physics_motion_exclusions_2d", "physics_exception_pairs_2d", "physics_exception_pairs_3d", "physics_one_way_overflow_2d",
)
RENDER_CASES = frozenset(("render_2d", "render_3d", "render_ellipse_2d", "render_light_culling_3d", "render_multimesh_3d"))
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
    if sys.platform == "darwin":
        return macos_ps_rss_mib(pid)
    return None


def macos_ps_rss_mib(pid: int) -> float | None:
    """Get resident KiB from ps on macOS when psutil is unavailable."""
    try:
        result = subprocess.run(
            ["ps", "-o", "rss=", "-p", str(pid)],
            capture_output=True, text=True, timeout=1.0, check=False,
        )
        if result.returncode != 0:
            return None
        kib = result.stdout.strip()
        return int(kib) / 1024.0 if kib else None
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return None


def sampling_interval_seconds(operating_system: str, psutil_available: bool) -> float:
    """Reduce ps subprocess overhead on macOS without psutil."""
    return 0.25 if operating_system == "darwin" and not psutil_available else 0.05


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
             case: str, scale: int, frames: int, seed: int,
             require_marker: bool = True) -> dict[str, Any]:
    start = time.monotonic()
    try:
        import psutil  # type: ignore[import-not-found]
        psutil_available = True
    except ImportError:
        psutil_available = False
    sample_interval = sampling_interval_seconds(sys.platform, psutil_available)
    maximum_rss: float | None = None
    latest_cpu: float | None = None
    peak_processes = 0
    failure = None
    # A file, rather than a PIPE, avoids deadlock if the engine emits megabytes of errors.
    with tempfile.TemporaryFile(mode="w+t", encoding="utf-8", errors="replace") as output:
        try:
            process = subprocess.Popen(cmd, stdout=output, stderr=subprocess.STDOUT,
                                       **isolation_options())
        except OSError as exc:
            return {"status": "failed", "failure": "launch: %s" % exc,
                    "wall_seconds": 0.0, "peak_rss_mib": None, "exit_code": None}
        while process.poll() is None:
            elapsed = time.monotonic() - start
            current_rss, current_cpu, process_count = sample_process_tree(process.pid)
            peak_processes = max(peak_processes, process_count)
            if current_cpu is not None:
                latest_cpu = max(latest_cpu or 0.0, current_cpu)
            if current_rss is not None:
                maximum_rss = max(maximum_rss or 0.0, current_rss)
                if current_rss > rss_limit_mib:
                    failure = "rss_limit_exceeded"
            if elapsed > timeout:
                failure = "timeout"
            elif elapsed > 1.0 and maximum_rss is None:
                # Do not report an enforced RAM limit if monitoring is absent.
                failure = "rss_monitor_unavailable"
            if failure is not None:
                kill_group(process)
                break
            time.sleep(sample_interval)
        process.wait()
        elapsed = time.monotonic() - start
        # Avoid unbounded RAM usage when a child emits a large error log.
        output.seek(0, os.SEEK_END)
        log_size = output.tell()
        output.seek(max(0, log_size - 2 * 1024 * 1024))
        log = output.read()
    result: dict[str, Any] = {
        "status": "passed",
        "wall_seconds": round(elapsed, 6),
        "peak_rss_mib": round(maximum_rss, 3) if maximum_rss is not None else None,
        "cpu_seconds": round(latest_cpu, 6) if latest_cpu is not None else None,
        "peak_processes": peak_processes,
        "exit_code": process.returncode,
    }
    if failure is None and process.returncode != 0:
        failure = "engine_exit_%d" % process.returncode
    if failure is None and ENGINE_ERROR.search(log):
        failure = "engine_error_log"
    if failure is None and require_marker:
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
    engine_times = sorted(r["engine"]["duration_ms"] for r in passed if r.get("engine"))
    engine_memory = [r["engine"]["engine_memory_after_bytes"] for r in passed
                     if isinstance(r.get("engine"), dict) and isinstance(r["engine"].get("engine_memory_after_bytes"), (int, float))]
    phase_values: dict[str, list[float]] = {}
    for run in passed:
        engine = run.get("engine")
        detail = engine.get("detail", {}) if isinstance(engine, dict) else {}
        if not isinstance(detail, dict):
            continue
        for metric, value in detail.items():
            if (metric.endswith("_ms") and isinstance(value, (int, float))
                    and not isinstance(value, bool) and math.isfinite(value) and value >= 0):
                phase_values.setdefault(metric, []).append(float(value))
    # Incomplete or intermittently missing metrics would mislead a baseline.
    phase_medians = {
        key: round(statistics.median(values), 6)
        for key, values in sorted(phase_values.items())
        if len(values) == len(passed)
    }

    return {
        "status": "passed" if len(passed) == len(runs) else "failed",
        "median_wall_seconds": round(statistics.median(wall), 6) if wall else None,
        "p95_wall_seconds": round(wall[math.ceil(0.95 * len(wall)) - 1], 6) if wall else None,
        "p99_wall_seconds": round(wall[math.ceil(0.99 * len(wall)) - 1], 6) if wall else None,
        "max_rss_mib": round(max(memories), 3) if memories else None,
        "max_processes": max((r.get("peak_processes", 0) for r in runs), default=0),
        "median_cpu_seconds": round(statistics.median(cpu_times), 6) if cpu_times else None,
        "median_engine_ms": round(statistics.median(engine_times), 6) if engine_times else None,
        "p95_engine_ms": round(engine_times[math.ceil(0.95 * len(engine_times)) - 1], 6) if engine_times else None,
        "max_engine_memory_bytes": max(engine_memory) if engine_memory else None,
        "phase_median_ms": phase_medians,
        "runs": runs,
    }



def check_absolute_limits(cases: dict[str, Any], max_frame_ms: float | None,
                          max_physics_ms: float | None, max_vram_mib: float | None) -> list[str]:
    """Enforce explicit local budgets against measured scenario maxima."""
    failures = []
    metrics = (
        ("peak_frame_ms", max_frame_ms, "ms"),
        ("peak_physics_ms", max_physics_ms, "ms"),
        ("peak_video_memory_bytes", None if max_vram_mib is None else max_vram_mib * 1048576, "bytes"),
    )
    for case_name, case in cases.items():
        for number, run in enumerate(case.get("runs", []), start=1):
            if run.get("status") != "passed":
                continue
            detail = run.get("engine", {}).get("detail", {})
            if not isinstance(detail, dict):
                continue
            for field, limit, unit in metrics:
                if limit is None or field not in detail:
                    continue
                reading = detail[field]
                if not isinstance(reading, (int, float)) or not math.isfinite(reading) or reading < 0:
                    failures.append("%s #%d invalid %s: %r" % (case_name, number, field, reading))
                elif reading > limit:
                    failures.append("%s #%d %s: %.3f %s > %.3f %s" % (
                        case_name, number, field, reading, unit, limit, unit))
    return failures


def compare_baseline(current: dict[str, Any], baseline: dict[str, Any],
                     percent: float, memory_growth_limit_mib: float | None) -> list[str]:
    errors: list[str] = []
    keys = ("preset", "scale", "frames", "render_mode", "seed", "rss_scope")
    for key in keys:
        if current.get("configuration", {}).get(key) != baseline.get("configuration", {}).get(key):
            raise ValueError("Baseline configuration mismatch: %s" % key)
    for name, data in current["cases"].items():
        previous = baseline.get("cases", {}).get(name)
        if not previous or data["status"] != "passed":
            continue
        for field in ("median_wall_seconds", "median_cpu_seconds", "median_engine_ms", "p95_engine_ms", "max_rss_mib"):
            new, old = data.get(field), previous.get(field)
            if new is not None and old is not None and old > 0 and new > old * (1 + percent / 100.0):
                errors.append("%s %s: %.3f > %.3f (baseline + %.1f%%)" %
                              (name, field, new, old, percent))
        current_phases = data.get("phase_median_ms", {})
        previous_phases = previous.get("phase_median_ms", {})
        for metric in sorted(current_phases.keys() & previous_phases.keys()):
            new = current_phases[metric]
            old = previous_phases[metric]
            if old > 0 and new > old * (1 + percent / 100.0):
                errors.append("%s %s: %.3f ms > %.3f ms (baseline + %.1f%%)" %
                              (name, metric, new, old, percent))
    if memory_growth_limit_mib is not None:
        for case_name in ("memory_churn", "object_lifecycle", "scene_churn"):
            for run in current["cases"].get(case_name, {}).get("runs", []):
                if run["status"] != "passed":
                    continue
                retained_bytes = run.get("engine", {}).get("detail", {}).get("retained_growth_bytes")
                if not isinstance(retained_bytes, (int, float)) or not math.isfinite(retained_bytes):
                    continue
                growth = retained_bytes / 1048576.0
                if growth > memory_growth_limit_mib:
                    errors.append("%s retained growth %.3f MiB > %.3f MiB" %
                                  (case_name, growth, memory_growth_limit_mib))
    return errors



def markdown_hotspots(report: dict[str, Any]) -> str:
    """Human-readable ranking; distinct workloads are not normalized to identical work."""
    rows = []
    for case, values in report["cases"].items():
        if values.get("median_wall_seconds") is None:
            continue
        wall = values["median_wall_seconds"]
        p95 = values.get("p95_wall_seconds")
        rss = values.get("max_rss_mib")
        engine = values.get("median_engine_ms")
        note = []
        if p95 is not None and wall > 0 and p95 / wall >= 1.5:
            note.append("high run-to-run variability")
        cap = report.get("configuration", {}).get("rss_limit_mib")
        if rss is not None and isinstance(cap, (int, float)) and cap > 0 and rss >= cap * 0.8:
            note.append("near RSS limit")
        if engine is not None and wall > 0 and wall - engine / 1000.0 > max(0.25, wall * 0.5):
            note.append("startup/teardown dominates")
        rows.append((case, wall, p95, rss, engine, "; ".join(note)))
    rows.sort(key=lambda item: item[1], reverse=True)

    def number(value: float | None) -> str:
        return "%.3f" % value if value is not None else "n/a"

    lines = [
        "# Cgame stress: expensive workloads",
        "",
        "Preset: %s; scale: %s; mode: %s; status: %s." % (
            report["configuration"]["preset"], report["configuration"]["scale"],
            report["configuration"]["render_mode"], report["status"]),
        "",
        "Ordered by median wall time, **not** normalized workload throughput. "
        "Compare the same case and preset on identical hardware to identify regressions.",
        "",
        "| Scenario | Median wall (s) | p95 wall (s) | Peak RSS (MiB) | Engine median (ms) | Signals |",
        "| --- | ---: | ---: | ---: | ---: | --- |",
    ]
    for case, wall, p95, rss, engine, note in rows:
        lines.append("| %s | %s | %s | %s | %s | %s |" % (
            case, number(wall), number(p95), number(rss), number(engine), note or "—"))
    phase_rows = [
        (case, metric, value)
        for case, stats in report["cases"].items()
        for metric, value in stats.get("phase_median_ms", {}).items()
    ]
    if phase_rows:
        lines += [
            "", "## In-engine phase metrics",
            "",
            "Phase medians are comparable only within the same case and fixed "
            "workload; frame measurements can include scheduling and waiting.",
            "",
            "| Scenario | Detail metric | Median (ms) |",
            "| --- | --- | ---: |",
        ]
        for case, metric, value in sorted(phase_rows, key=lambda row: row[2], reverse=True):
            lines.append("| %s | %s | %s |" % (case, metric, number(value)))
    lines += ["", "Failures: %d" % len(report["failures"])]
    lines.extend("- %s" % str(message).replace("\n", " ") for message in report["failures"])
    lines.append("")
    return "\n".join(lines)


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
    parser.add_argument("--max-frame-ms", type=float, help="Maximum observed script/frame time (ms), for cases reporting it")
    parser.add_argument("--max-physics-ms", type=float, help="Maximum observed physics process time (ms)")
    parser.add_argument("--max-vram-mib", type=float, help="Maximum observed renderer video memory (MiB)")
    parser.add_argument("--output", type=Path, default=Path("stress-results.json"))
    parser.add_argument("--summary-md", type=Path, help="Also write a ranked human-readable bottleneck report")
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
            or any(value is not None and value < 0 for value in (
                args.max_frame_ms, args.max_physics_ms, args.max_vram_mib))
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
        "schema_version": 2,
        "created_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "host": {"platform": platform.platform(), "processor": platform.processor(),
                 "logical_cpus": os.cpu_count()},
        "godot_binary": binary,
        "configuration": {"preset": args.preset, "scale": config["scale"],
                          "frames": config["frames"], "repeats": config["repeats"],
                          "render_mode": args.render_mode, "rss_scope": "process_tree",
                          "timeout_seconds": config["timeout"],
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

    report["failures"].extend(check_absolute_limits(
        report["cases"], args.max_frame_ms, args.max_physics_ms, args.max_vram_mib))
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
    if args.summary_md is not None:
        args.summary_md.parent.mkdir(parents=True, exist_ok=True)
        args.summary_md.write_text(markdown_hotspots(report), encoding="utf-8")
    print("Stress report: %s (%s)" % (args.output, report["status"]))
    for error in report["failures"]:
        print("FAIL: " + error, file=sys.stderr)
    return 1 if report["failures"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
