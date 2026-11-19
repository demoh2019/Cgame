#!/usr/bin/env python3
"""Content-hash incremental Godot asset imports for local builds and CI.

This wrapper delegates importing to Godot itself. It skips unchanged projects,
reports precise source changes, and never marks failed imports as successful.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile

CACHE_VERSION = 1
STATE_NAME = "cgame-import-state.json"
IGNORE_DIRS = frozenset({".godot", ".git", ".hg", ".svn", ".venv", "venv", "__pycache__", "node_modules"})
BLOCK_SIZE = 1024 * 1024
MAX_STATE_BYTES = 16 * 1024 * 1024


class ImportPipelineError(Exception):
    """Invalid project, unsafe file layout, or failed Godot invocation."""


def inventory(root: Path) -> dict[str, str]:
    """Hash regular source files; do not follow links outside or inside projects."""
    root = Path(root).resolve()
    if not (root / "project.godot").is_file():
        raise ImportPipelineError(f"Missing project.godot in {root}")
    entries: dict[str, str] = {}

    def fail_walk(err: OSError) -> None:
        raise ImportPipelineError(f"Cannot enumerate project files: {err}") from err

    for base, dirs, files in os.walk(root, topdown=True, followlinks=False, onerror=fail_walk):
        base_path = Path(base)
        for dirname in dirs:
            if (base_path / dirname).is_symlink():
                raise ImportPipelineError(f"Symlinked directory: {(base_path / dirname).relative_to(root)}")
        dirs[:] = sorted(d for d in dirs if d not in IGNORE_DIRS)
        for name in sorted(files):
            path = base_path / name
            rel = path.relative_to(root).as_posix()
            if path.is_symlink():
                raise ImportPipelineError(f"Symlinked file: {rel}")
            before = path.stat()
            if not stat.S_ISREG(before.st_mode):
                raise ImportPipelineError(f"Not a regular file: {rel}")
            digest = hashlib.sha256()
            with path.open("rb") as handle:
                while data := handle.read(BLOCK_SIZE):
                    digest.update(data)
                after = os.fstat(handle.fileno())
            if (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns) != (
                after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns
            ):
                raise ImportPipelineError(f"File changed while hashing: {rel}")
            entries[rel] = digest.hexdigest()
    return dict(sorted(entries.items()))


def load_state(path: Path) -> dict | None:
    """Treat corrupt/obsolete state as a cache miss, never as a cache hit."""
    try:
        if path.is_symlink() or path.stat().st_size > MAX_STATE_BYTES:
            return None
        state = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, ValueError):
        return None
    if not isinstance(state, dict) or state.get("schema") != CACHE_VERSION:
        return None
    files = state.get("files")
    if not isinstance(files, dict) or not isinstance(state.get("engine"), str):
        return None
    if not all(isinstance(k, str) and isinstance(v, str) and len(v) == 64
               and all(ch in "0123456789abcdef" for ch in v) for k, v in files.items()):
        return None
    return state


def make_plan(current: dict[str, str], previous: dict | None, engine: str,
              cache_exists: bool, force: bool = False) -> dict:
    old = previous["files"] if previous else {}
    added = sorted(current.keys() - old.keys())
    changed = sorted(k for k in current.keys() & old.keys() if current[k] != old[k])
    removed = sorted(old.keys() - current.keys())
    reason = []
    if previous is None:
        reason.append("missing_state")
    elif previous["engine"] != engine:
        reason.append("engine_changed")
    if not cache_exists:
        reason.append("missing_godot_cache")
    if force:
        reason.append("forced")
    return {
        "needs_import": bool(added or changed or removed or reason),
        "reasons": reason, "added": added, "changed": changed, "removed": removed,
        "files_scanned": len(current),
    }


def save_state(path: Path, state: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.is_symlink() or path.parent.is_symlink():
        raise ImportPipelineError("Unsafe import state path (symlink)")
    fd, temporary = tempfile.mkstemp(prefix=".import-state-", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump(state, stream, sort_keys=True, indent=2)
            stream.write("\n")
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def run_pipeline(root: Path, godot: str = "godot", force: bool = False,
                 dry_run: bool = False, timeout: int = 900,
                 runner=subprocess.run) -> dict:
    root = Path(root).resolve()
    if timeout < 1:
        raise ImportPipelineError("timeout must be positive")
    state_path = root / ".godot" / STATE_NAME
    # Do not trust a symlinked cache directory for reads or atomic writes.
    if (root / ".godot").is_symlink() or state_path.is_symlink():
        raise ImportPipelineError("Unsafe .godot cache path (symlink)")
    current = inventory(root)
    try:
        version = runner([godot, "--version"], cwd=str(root), text=True,
                         capture_output=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise ImportPipelineError(f"Unable to query Godot version: {exc}") from exc
    if version.returncode != 0 or not version.stdout.strip():
        raise ImportPipelineError("Godot version command failed")
    engine = version.stdout.strip()
    previous = load_state(state_path)
    cache_exists = (root / ".godot").is_dir()
    plan = make_plan(current, previous, engine, cache_exists, force)
    plan["engine"] = engine
    plan["status"] = "dry_run" if dry_run else ("skipped" if not plan["needs_import"] else "pending")
    if dry_run or not plan["needs_import"]:
        return plan
    try:
        completed = runner([godot, "--headless", "--path", str(root), "--import"],
                           cwd=str(root), timeout=timeout)
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise ImportPipelineError(f"Godot asset import failed: {exc}") from exc
    if completed.returncode != 0:
        raise ImportPipelineError(f"Godot import returned exit code {completed.returncode}")
    if inventory(root) != current:
        raise ImportPipelineError("Project inputs changed during import; state not saved")
    save_state(state_path, {"schema": CACHE_VERSION, "engine": engine, "files": current})
    plan["status"] = "imported"
    return plan


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", nargs="?", type=Path, default=Path("."), help="Godot project root")
    parser.add_argument("--godot", default="godot", help="Godot editor executable")
    parser.add_argument("--force", action="store_true", help="Import even if unchanged")
    parser.add_argument("--dry-run", action="store_true", help="Show proposed work without importing")
    parser.add_argument("--timeout", type=int, default=900, help="Seconds per Godot command")
    parser.add_argument("--json", action="store_true", help="Machine-readable plan and result")
    args = parser.parse_args(argv)
    try:
        result = run_pipeline(args.root, args.godot, args.force, args.dry_run, args.timeout)
    except ImportPipelineError as exc:
        print(f"Import pipeline: {exc}", file=sys.stderr)
        return 2
    if args.json:
        print(json.dumps(result, sort_keys=True, ensure_ascii=False))
    else:
        print(f"Asset import {result['status']}: {result['files_scanned']} files; "
              f"{len(result['added'])} added, {len(result['changed'])} changed, "
              f"{len(result['removed'])} removed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
