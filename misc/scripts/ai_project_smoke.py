#!/usr/bin/env python3
"""Opt-in headless Godot checks on an isolated *copy* of an AI-generated project.

Staging protects original project files from accidental edits. It is NOT a
security sandbox: Godot can execute scripts during import or gameplay.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile

from ai_diagnostics import MAX_DIAGNOSTICS, scan_log, scan_text

MIB = 1024 * 1024
SKIP_DIRS = frozenset({".git", ".godot", ".import", ".hg", ".svn", "__pycache__"})
MAX_LOG_BYTES = 64 * 1024


class SmokeError(Exception):
    """Unable to create a complete snapshot or launch the requested check."""


def snapshot_project(source: Path, target: Path, *, max_files: int = 20000,
                     max_bytes: int = 512 * MIB) -> dict:
    """Copy regular source files without following final-component symlinks."""
    source = Path(source).absolute()
    target = Path(target).absolute()
    if source.is_symlink() or not source.is_dir():
        raise SmokeError("project root must be a real directory")
    if max_files < 1 or max_bytes < 0:
        raise SmokeError("snapshot budgets must be non-negative")
    if not (source / "project.godot").is_file() or (source / "project.godot").is_symlink():
        raise SmokeError("missing regular project.godot")
    if target == source or source in target.parents or target in source.parents:
        raise SmokeError("snapshot target must be outside the source directory")
    target.mkdir(parents=True, exist_ok=True)
    count = 0
    copied_bytes = 0

    def walk_error(exc: OSError) -> None:
        raise SmokeError(f"cannot scan project: {exc}")

    for folder, dirs, names in os.walk(source, followlinks=False, onerror=walk_error):
        here = Path(folder)
        for name in dirs:
            if name not in SKIP_DIRS and (here / name).is_symlink():
                raise SmokeError(f"symlink directory: {(here / name).relative_to(source)}")
        dirs[:] = sorted(name for name in dirs if name not in SKIP_DIRS)
        relative_dir = here.relative_to(source)
        (target / relative_dir).mkdir(parents=True, exist_ok=True)
        for name in sorted(names):
            input_path = here / name
            relative = input_path.relative_to(source)
            try:
                before = input_path.lstat()
            except OSError as exc:
                raise SmokeError(f"cannot stat {relative}: {exc}") from exc
            if not stat.S_ISREG(before.st_mode):
                raise SmokeError(f"symlink or non-regular file: {relative}")
            if count + 1 > max_files or copied_bytes + before.st_size > max_bytes:
                raise SmokeError("project exceeds snapshot file or byte budget")
            output_path = target / relative
            flags = os.O_RDONLY | getattr(os, "O_BINARY", 0) | getattr(os, "O_NOFOLLOW", 0)
            try:
                descriptor = os.open(input_path, flags)
                with os.fdopen(descriptor, "rb") as reader, output_path.open("xb") as writer:
                    opened = os.fstat(reader.fileno())
                    if not stat.S_ISREG(opened.st_mode) or (opened.st_dev, opened.st_ino) != (before.st_dev, before.st_ino):
                        raise SmokeError(f"source file changed during snapshot: {relative}")
                    read_bytes = 0
                    while chunk := reader.read(1024 * 1024):
                        read_bytes += len(chunk)
                        if read_bytes > before.st_size:
                            raise SmokeError(f"file grew during snapshot: {relative}")
                        writer.write(chunk)
                    after = os.fstat(reader.fileno())
                    if (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns) != (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns) or read_bytes != before.st_size:
                        raise SmokeError(f"source file changed during snapshot: {relative}")
            except (OSError, ValueError) as exc:
                raise SmokeError(f"cannot copy {relative}: {exc}") from exc
            count += 1
            copied_bytes += before.st_size
    return {"files": count, "bytes": copied_bytes}


def _resolve_godot(program: str) -> str:
    resolved = shutil.which(program)
    if not resolved:
        raise SmokeError("Godot executable not found (specify --godot)")
    return resolved


def _child_environment(workspace: Path) -> dict[str, str]:
    """Avoid inheriting common API-key environment variables by default."""
    allow = ("PATH", "SYSTEMROOT", "WINDIR", "LANG", "LC_ALL", "LD_LIBRARY_PATH", "DYLD_LIBRARY_PATH")
    env = {key: os.environ[key] for key in allow if key in os.environ}
    home = str(workspace / "home")
    (workspace / "home").mkdir(exist_ok=True)
    env.update({"HOME": home, "XDG_CONFIG_HOME": home, "XDG_DATA_HOME": home,
                "XDG_CACHE_HOME": home, "TMPDIR": home, "TEMP": home, "TMP": home})
    return env


def _sample_output(logfile, max_bytes: int) -> tuple[str, bool]:
    logfile.seek(0, os.SEEK_END)
    length = logfile.tell()
    if length <= max_bytes:
        logfile.seek(0)
        data = logfile.read()
        return data.decode("utf-8", errors="replace"), False
    size = max_bytes // 2
    logfile.seek(0)
    first = logfile.read(size)
    logfile.seek(-size, os.SEEK_END)
    last = logfile.read(size)
    return (first.decode("utf-8", errors="replace") + "\n[... output truncated ...]\n" +
            last.decode("utf-8", errors="replace")), True


def _diagnostics(text: str, stage: Path) -> tuple[list[str], list[str]]:
    """Compatibility API for callers that need only bounded text messages."""
    findings = scan_text(text, stage)
    return findings["errors"], findings["warnings"]


def _scan_log_diagnostics(logfile, stage: Path) -> tuple[list[str], list[str], int, int]:
    """Backward-compatible full-file scanner; share parsing with repair reports."""
    findings = scan_log(logfile, stage)
    return (findings["errors"], findings["warnings"],
            findings["error_count"], findings["warning_count"])


def _run_stage(godot: str, stage: Path, name: str, timeout: float,
               workspace: Path, max_log_bytes: int = MAX_LOG_BYTES) -> dict:
    args = [godot, "--headless", "--path", str(stage)]
    args += ["--import"] if name == "import" else ["--quit-after", "2"]
    with tempfile.TemporaryFile(mode="w+b") as logfile:
        try:
            process = subprocess.Popen(args, stdout=logfile, stderr=subprocess.STDOUT,
                                       cwd=workspace, env=_child_environment(workspace))
        except OSError as exc:
            raise SmokeError(f"cannot start Godot: {exc}") from exc
        timed_out = False
        try:
            process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            process.kill()
            process.wait()
        _, truncated = _sample_output(logfile, max_log_bytes)
        # Read the entire log: a relevant error may lie outside the sampled head/tail.
        findings = scan_log(logfile, stage)
    return {"name": name,
            "ok": not timed_out and process.returncode == 0 and findings["error_count"] == 0,
            "exit_code": process.returncode, "timed_out": timed_out,
            "output_truncated": truncated,
            "errors": findings["errors"], "warnings": findings["warnings"],
            "error_count": findings["error_count"], "warning_count": findings["warning_count"],
            "diagnostics_truncated": (findings["error_count"] > len(findings["errors"]) or
                                      findings["warning_count"] > len(findings["warnings"])),
            "diagnostics": findings["diagnostics"]}


def check_project(source: Path, *, godot: str = "godot", timeout: float = 90,
                  run_game: bool = False, max_files: int = 20000,
                  max_bytes: int = 512 * MIB) -> dict:
    """Explicitly launched execution; never call this on untrusted projects without consent."""
    if not 0 < timeout <= 600:
        raise SmokeError("timeout must be in (0, 600] seconds")
    program = _resolve_godot(godot)
    with tempfile.TemporaryDirectory(prefix="godot-ai-smoke-") as temporary:
        workspace = Path(temporary)
        stage = workspace / "project"
        copied = snapshot_project(source, stage, max_files=max_files, max_bytes=max_bytes)
        checks = [_run_stage(program, stage, "import", timeout, workspace)]
        if run_game and checks[0]["ok"]:
            checks.append(_run_stage(program, stage, "game", timeout, workspace))
        return {"format": 1, "ok": all(item["ok"] for item in checks),
                "snapshot": copied, "checks": checks}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("project", type=Path)
    parser.add_argument("--godot", default="godot", help="Godot editor executable")
    parser.add_argument("--timeout", type=float, default=90.0, help="Seconds per stage (max 600)")
    parser.add_argument("--run-game", action="store_true", help="Also start the main scene for two frames")
    parser.add_argument("--max-copy-mib", type=int, default=512)
    parser.add_argument("--max-files", type=int, default=20000)
    parser.add_argument("--approve-execution", action="store_true", help="Required: allow Godot to run project/editor scripts")
    args = parser.parse_args(argv)
    if not args.approve_execution:
        print("ai_project_smoke: execution requires --approve-execution; Godot scripts are not sandboxed", file=sys.stderr)
        return 2
    try:
        report = check_project(args.project, godot=args.godot, timeout=args.timeout,
                               run_game=args.run_game, max_files=args.max_files,
                               max_bytes=args.max_copy_mib * MIB)
    except (SmokeError, OSError) as exc:
        print(f"ai_project_smoke: {exc}", file=sys.stderr)
        return 2
    print(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True))
    return 0 if report["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
