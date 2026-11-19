#!/usr/bin/env python3
"""Check AI-generated GDScript with Godot and optionally smoke-run a scene.

Requires Python 3.9+ and a compatible Godot 4 executable. This script is
explicitly user-invoked; it never executes generated game code unless
--smoke-run is supplied. Godot --check-only only parses a script.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path
from time import monotonic
from typing import Any

MAX_OUTPUT_CHARS = 16000
DEFAULT_MAX_FILES = 200
DEFAULT_TIMEOUT = 30
MAIN_SCENE = "res://ai_generated/main.tscn"


def discover_scripts(project: Path, max_files: int = DEFAULT_MAX_FILES) -> list[str]:
    """List generated .gd files without following links outside the project."""
    root = (project / "ai_generated")
    if not root.is_dir():
        raise FileNotFoundError(f"Missing generated directory: {root}")
    project = project.resolve(strict=True)
    if not root.resolve(strict=True).is_relative_to(project):
        raise ValueError("Generated directory points outside the project")
    scripts: list[str] = []
    for file in sorted(root.rglob("*.gd")):
        if file.is_symlink() or not file.is_file():
            continue
        resolved = file.resolve(strict=True)
        if not resolved.is_relative_to(root.resolve(strict=True)):
            continue
        if any(parent.is_symlink() for parent in file.parents if parent != root.parent):
            continue
        scripts.append("res://" + file.relative_to(project).as_posix())
        if len(scripts) > max_files:
            raise ValueError(f"More than {max_files} scripts: split your project")
    return scripts


def script_command(godot: str, project: Path, resource: str) -> list[str]:
    return [godot, "--headless", "--path", str(project), "--check-only", "--script", resource]


def smoke_command(godot: str, project: Path, scene: str = MAIN_SCENE) -> list[str]:
    return [godot, "--headless", "--path", str(project), "--scene", scene, "--quit-after", "3"]


def run_check(kind: str, resource: str, command: list[str], timeout: int) -> dict[str, Any]:
    started = monotonic()
    try:
        result = subprocess.run(
            command, check=False, capture_output=True, text=True,
            encoding="utf-8", errors="replace", timeout=timeout,
        )
        output = (result.stdout + "\n" + result.stderr).strip()[:MAX_OUTPUT_CHARS]
        # Some Godot versions report parser failures without a nonzero code.
        parser_error = any(marker in output for marker in (
            "SCRIPT ERROR:", "Parse Error:", "Parser Error:",
        ))
        return {
            "kind": kind, "path": resource, "ok": result.returncode == 0 and not parser_error,
            "exit_code": result.returncode, "output": output,
            "duration_ms": round((monotonic() - started) * 1000),
        }
    except subprocess.TimeoutExpired as error:
        return {
            "kind": kind, "path": resource, "ok": False, "exit_code": None,
            "output": f"Godot exceeded {timeout}s timeout: {error}",
            "duration_ms": round((monotonic() - started) * 1000),
        }
    except OSError as error:
        return {
            "kind": kind, "path": resource, "ok": False, "exit_code": None,
            "output": f"Could not start Godot: {error}",
            "duration_ms": round((monotonic() - started) * 1000),
        }


def evaluate(godot: str, project: Path, timeout: int = DEFAULT_TIMEOUT,
             max_files: int = DEFAULT_MAX_FILES, smoke_run: bool = False) -> dict[str, Any]:
    project = project.resolve(strict=True)
    if not (project / "project.godot").is_file():
        raise FileNotFoundError(f"Missing project.godot in {project}")
    if timeout < 1 or timeout > 120:
        raise ValueError("Timeout must be between 1 and 120 seconds")
    if max_files < 1 or max_files > 2000:
        raise ValueError("max-files must be between 1 and 2000")

    scripts = discover_scripts(project, max_files)
    checks = [run_check("gdscript_parse", script, script_command(godot, project, script), timeout)
              for script in scripts]
    if smoke_run:
        scene = project / "ai_generated" / "main.tscn"
        if not scene.is_file() or scene.is_symlink() or not scene.resolve().is_relative_to(project):
            checks.append({"kind": "scene_smoke", "path": MAIN_SCENE, "ok": False,
                           "exit_code": None, "output": "Missing or unsafe main scene", "duration_ms": 0})
        else:
            checks.append(run_check("scene_smoke", MAIN_SCENE,
                                    smoke_command(godot, project), timeout))
    return {
        "version": 1, "project": str(project), "godot": godot,
        "smoke_run": smoke_run,
        "checks": checks,
        "summary": {
            "total": len(checks), "passed": sum(check["ok"] for check in checks),
            "failed": sum(not check["ok"] for check in checks),
        },
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, required=True, help="Godot project directory")
    parser.add_argument("--godot", default="godot", help="Godot 4 executable name or path")
    parser.add_argument("--timeout", type=int, default=DEFAULT_TIMEOUT, help="Seconds per check (1-120)")
    parser.add_argument("--max-files", type=int, default=DEFAULT_MAX_FILES)
    parser.add_argument("--report", type=Path, help="Write a machine-readable JSON report")
    parser.add_argument("--smoke-run", action="store_true",
                        help="Run untrusted generated game code for 3 headless frames; only in a sandbox")
    args = parser.parse_args(argv)
    try:
        report = evaluate(args.godot, args.project, args.timeout, args.max_files, args.smoke_run)
    except (OSError, ValueError) as error:
        print(f"AI game validation failed to start: {error}", file=sys.stderr)
        return 2
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"Checked {report['summary']['total']} item(s): "
          f"{report['summary']['passed']} passed, {report['summary']['failed']} failed.")
    for check in report["checks"]:
        if not check["ok"]:
            print(f"ERROR: {check['path']}\n{check['output']}")
    return 1 if report["summary"]["failed"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
