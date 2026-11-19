#!/usr/bin/env python3
"""Deterministic size report and CI budgets for Godot project source files."""

from __future__ import annotations

import argparse
import json
from heapq import nsmallest
import math
import os
from pathlib import Path
import stat
import sys

SKIP_DIRS = frozenset({".git", ".godot", ".import", ".hg", ".svn", "__pycache__"})
MIB = 1024 * 1024


class AssetSizeError(Exception):
    """A scan could not produce a trustworthy complete inventory."""


def parse_mib(value: str) -> int:
    """Parse a non-negative number of MiB into an integer byte budget."""
    try:
        number = float(value)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("budget must be a number of MiB") from exc
    if not math.isfinite(number) or not math.isfinite(number * MIB) or number < 0:
        raise argparse.ArgumentTypeError("budget must be finite and non-negative")
    return int(number * MIB)


def scan(root: Path, top: int = 20, max_total: int | None = None,
         max_file: int | None = None) -> dict:
    root = Path(root)
    if root.is_symlink() or not root.is_dir():
        raise AssetSizeError("project root must be a real directory")
    if top < 0 or any(v is not None and v < 0 for v in (max_total, max_file)):
        raise AssetSizeError("limits and top must be non-negative")

    files: list[tuple[str, int]] = []

    def walk_error(error: OSError) -> None:
        raise AssetSizeError(f"cannot read project directory: {error}")

    for current, dirs, names in os.walk(root, followlinks=False, onerror=walk_error):
        base = Path(current)
        for name in dirs:
            if name in SKIP_DIRS:
                continue
            if (base / name).is_symlink():
                raise AssetSizeError(f"symlink directory: {(base / name).relative_to(root)}")
        dirs[:] = sorted(name for name in dirs if name not in SKIP_DIRS)
        for name in sorted(names):
            path = base / name
            relative = path.relative_to(root).as_posix()
            try:
                info = path.lstat()
            except OSError as exc:
                raise AssetSizeError(f"cannot stat {relative}: {exc}") from exc
            if not stat.S_ISREG(info.st_mode):
                raise AssetSizeError(f"non-regular file or symlink: {relative}")
            files.append((relative, info.st_size))

    total = sum(size for _, size in files)
    extensions: dict[str, dict[str, int]] = {}
    directories: dict[str, dict[str, int]] = {}
    for path, size in files:
        ext = Path(path).suffix.lower() or "[none]"
        folder = path.split("/", 1)[0] if "/" in path else "[root]"
        for key, counts in ((ext, extensions), (folder, directories)):
            item = counts.setdefault(key, {"files": 0, "bytes": 0})
            item["files"] += 1
            item["bytes"] += size

    # Limit the selection heap to requested output size instead of sorting
    # every asset when the usual report needs only a small top-N.
    rank_key = lambda item: (-item[1], item[0])
    # Sorting violations is necessary for deterministic diagnostics, but
    # passing assets never need to be part of that sort.
    violating_files = (sorted((item for item in files if item[1] > max_file), key=rank_key)
                       if max_file is not None else [])
    # If the violations already fill the top-N they are the top-N of all
    # assets too, so reuse the ranked list rather than sorting a second time.
    largest = (violating_files[:top] if len(violating_files) >= top
               else nsmallest(top, files, key=rank_key))
    violations: list[dict] = []
    if max_total is not None and total > max_total:
        violations.append({"kind": "total", "bytes": total, "limit_bytes": max_total})
    if max_file is not None:
        violations.extend({"kind": "file", "path": path, "bytes": size, "limit_bytes": max_file}
                          for path, size in violating_files)

    return {
        "format": 1,
        "summary": {"files": len(files), "total_bytes": total},
        "by_extension": dict(sorted(extensions.items())),
        "by_directory": dict(sorted(directories.items())),
        "largest": [{"path": path, "bytes": size} for path, size in largest],
        "violations": violations,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("project", type=Path, help="Root of the Godot project to audit")
    parser.add_argument("--top", type=int, default=20, help="Largest assets to include (default: 20)")
    parser.add_argument("--max-total-mib", type=parse_mib, help="Fail if source files exceed this budget")
    parser.add_argument("--max-file-mib", type=parse_mib, help="Fail if any source file exceeds this budget")
    args = parser.parse_args(argv)
    try:
        report = scan(args.project, args.top, args.max_total_mib, args.max_file_mib)
    except (AssetSizeError, OSError) as exc:
        print(f"project_asset_sizes: {exc}", file=sys.stderr)
        return 2
    print(json.dumps(report, ensure_ascii=False, sort_keys=True, indent=2))
    return 1 if report["violations"] else 0


if __name__ == "__main__":
    sys.exit(main())
