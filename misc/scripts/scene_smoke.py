#!/usr/bin/env python3
"""Bounded headless scene smoke tests for Godot projects (Python 3.9+)."""

import argparse
import fnmatch
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

SCENE_EXTENSIONS = {".tscn", ".scn"}
SKIP_DIRS = {".git", ".godot", ".hg", ".svn", "__pycache__"}
ERROR_LINE = re.compile(r"^\s*(?:SCRIPT ERROR:|ERROR:)", re.IGNORECASE | re.MULTILINE)
LOG_LIMIT = 6000


class SmokeError(Exception):
    """Invalid project or unsafe scene tree."""


def discover_scenes(root, exclude=(), max_scenes=1000):
    """Find scenes in a stable order, never following directory symlinks."""
    if root.is_symlink() or not root.is_dir() or not (root / "project.godot").is_file():
        raise SmokeError("Project root must be a directory with project.godot (not a symlink)")
    scenes = []
    seen = set()

    def walk_error(error):
        raise SmokeError("Cannot scan project: {}".format(error))

    for current, directories, files in os.walk(root, followlinks=False, onerror=walk_error):
        folder = Path(current)
        for directory in directories:
            entry = folder / directory
            if entry.is_symlink() and directory not in SKIP_DIRS:
                raise SmokeError("Scene tree contains a directory symlink: {}".format(entry))
        directories[:] = sorted(d for d in directories if d not in SKIP_DIRS)
        for name in sorted(files):
            if Path(name).suffix.lower() not in SCENE_EXTENSIONS:
                continue
            entry = folder / name
            if entry.is_symlink() or not entry.is_file():
                raise SmokeError("Unsafe scene file: {}".format(entry))
            relative = entry.relative_to(root).as_posix()
            if any(fnmatch.fnmatchcase(relative, pattern) for pattern in exclude):
                continue
            folded = relative.casefold()
            if folded in seen:
                raise SmokeError("Case-insensitive scene path collision: {}".format(relative))
            seen.add(folded)
            scenes.append(relative)
            if len(scenes) > max_scenes:
                raise SmokeError("Scene count exceeds --max-scenes={}".format(max_scenes))
    return sorted(scenes)


def run_command(args, timeout):
    """Return exit code, bounded diagnostics, timeout flag, and error marker flag."""
    try:
        proc = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              encoding="utf-8", errors="replace", timeout=timeout, check=False)
    except subprocess.TimeoutExpired as error:
        # TimeoutExpired.stdout/stderr may be bytes even with text=True.
        def decode(value):
            return value.decode("utf-8", "replace") if isinstance(value, bytes) else (value or "")
        output = decode(error.stdout) + "\n" + decode(error.stderr)
        return None, output[-LOG_LIMIT:], True, bool(ERROR_LINE.search(output))
    except OSError as error:
        raise SmokeError("Cannot execute Godot: {}".format(error)) from error
    output = proc.stdout + "\n" + proc.stderr
    return proc.returncode, output[-LOG_LIMIT:], False, bool(ERROR_LINE.search(output))


def run_suite(root, executable, scenes, timeout=30, frames=2, import_first=False):
    """Run each scene in its own process so one failure cannot stop the suite."""
    if import_first:
        code, log, timed_out, has_errors = run_command(
            [executable, "--headless", "--path", str(root), "--import"], timeout)
        if timed_out or code != 0 or has_errors:
            return {"ok": False, "import": {"status": "timeout" if timed_out else "fail", "exit_code": code, "log": log}, "results": []}
    results = []
    for relative in scenes:
        command = [executable, "--headless", "--path", str(root), "--scene",
                   "res://" + relative, "--quit-after", str(frames)]
        code, log, timed_out, has_errors = run_command(command, timeout)
        bad = timed_out or code != 0 or has_errors
        results.append({"scene": relative,
                        "status": "timeout" if timed_out else "fail" if bad else "pass",
                        "exit_code": code,
                        "log": log if bad else ""})
    return {"ok": all(r["status"] == "pass" for r in results), "results": results}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("project", type=Path, help="Path to an existing Godot 4 project")
    parser.add_argument("--godot", default="godot", help="Godot editor binary or path")
    parser.add_argument("--exclude", action="append", default=[], help="Scene glob to skip; repeatable")
    parser.add_argument("--timeout", type=int, default=30, help="Timeout per launch in seconds")
    parser.add_argument("--frames", type=int, default=2, help="Headless iterations per scene")
    parser.add_argument("--max-scenes", type=int, default=1000, help="Limit scene count")
    parser.add_argument("--import-first", action="store_true", help="Import project assets first")
    parser.add_argument("--format", choices=("text", "json"), default="text")
    opts = parser.parse_args(argv)
    try:
        if not 1 <= opts.timeout <= 3600 or not 1 <= opts.frames <= 10000 or not 1 <= opts.max_scenes <= 100000:
            raise SmokeError("timeout, frames and max-scenes must be positive and within their limits")
        root = opts.project.absolute()
        scenes = discover_scenes(root, opts.exclude, opts.max_scenes)
        binary = shutil.which(opts.godot)
        if binary is None:
            raise SmokeError("Godot editor binary not found: {}".format(opts.godot))
        report = run_suite(root, binary, scenes, opts.timeout, opts.frames, opts.import_first)
    except SmokeError as error:
        print("scene_smoke: {}".format(error), file=sys.stderr)
        return 2
    if opts.format == "json":
        print(json.dumps(report, ensure_ascii=False, sort_keys=True))
    else:
        if "import" in report:
            print("IMPORT {}".format(report["import"]["status"].upper()))
            if report["import"]["log"]:
                print(report["import"]["log"], file=sys.stderr)
        for result in report["results"]:
            print("{} {}".format(result["status"].upper(), result["scene"]))
            if result["log"]:
                print(result["log"], file=sys.stderr)
        print("{} scenes checked".format(len(report["results"])))
    return 0 if report["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
