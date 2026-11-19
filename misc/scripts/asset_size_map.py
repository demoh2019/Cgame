#!/usr/bin/env python3
"""Portable, read-only asset size map and budget checker for Godot projects."""

import argparse
import json
from heapq import nsmallest
import os
from pathlib import Path
import re
import stat
import sys

EXCLUDED_DIRECTORIES = frozenset({".git", ".godot", ".hg", ".svn", "__pycache__"})
EXTENSION_PATTERN = re.compile(r"(?:\.[a-z0-9_+-]+|\(none\))\Z")


class AssetSizeError(Exception):
    """An invalid project or unsafe asset makes the report incomplete."""


def _extension(name):
    return Path(name).suffix.casefold() or "(none)"


def scan_project(root):
    """Return a deterministic list of {path, extension, bytes} for a Godot project."""
    root = Path(root)
    if root.is_symlink() or not root.is_dir():
        raise AssetSizeError("Project root must be a real directory")
    marker = root / "project.godot"
    if marker.is_symlink() or not marker.is_file():
        raise AssetSizeError("Missing regular project.godot file")

    def walk_error(error):
        raise AssetSizeError("Cannot traverse project directory: {}".format(error))

    entries = []
    names_by_case = {}
    for current, directories, filenames in os.walk(root, followlinks=False, onerror=walk_error):
        directory = Path(current)
        # Check each directory's case-insensitive name once, instead of
        # rebuilding and casefolding every parent prefix for every asset.
        if directory != root:
            relative_directory = directory.relative_to(root).as_posix()
            alias = relative_directory.casefold()
            previous = names_by_case.setdefault(alias, relative_directory)
            if previous != relative_directory:
                raise AssetSizeError("Case-insensitive path collision: {} / {}".format(
                    previous, relative_directory))
        for name in list(directories):
            if name in EXCLUDED_DIRECTORIES:
                directories.remove(name)
            elif (directory / name).is_symlink():
                raise AssetSizeError("Symlinked directory: {}".format(directory / name))
        directories.sort()
        for name in sorted(filenames):
            full_path = directory / name
            relative = full_path.relative_to(root).as_posix()
            if full_path.is_symlink():
                raise AssetSizeError("Symlinked asset: {}".format(relative))
            details = full_path.stat(follow_symlinks=False)
            if not stat.S_ISREG(details.st_mode):
                raise AssetSizeError("Non-regular asset: {}".format(relative))
            alias = relative.casefold()
            previous = names_by_case.setdefault(alias, relative)
            if previous != relative:
                raise AssetSizeError("Case-insensitive path collision: {} / {}".format(
                    previous, relative))
            entries.append({"path": relative, "extension": _extension(name), "bytes": details.st_size})
    return sorted(entries, key=lambda item: item["path"])


def parse_extension_limits(specifications):
    """Parse repeated extension=bytes options, rejecting ambiguous settings."""
    result = {}
    for specification in specifications:
        extension, separator, raw_limit = specification.partition("=")
        extension = extension.casefold()
        if not separator or not EXTENSION_PATTERN.fullmatch(extension):
            raise AssetSizeError("Extension limit must look like .png=1048576 or (none)=100")
        if not raw_limit.isascii() or not raw_limit.isdecimal():
            raise AssetSizeError("Extension limit must be a nonnegative integer byte count")
        if extension in result:
            raise AssetSizeError("Duplicate extension limit: {}".format(extension))
        result[extension] = int(raw_limit)
    return result


def build_report(entries, top=10, total_limit=None, file_limit=None, extension_limits=None):
    """Summarize asset sizes and deterministic budget violations."""
    if not isinstance(top, int) or not 0 <= top <= 1000:
        raise AssetSizeError("Top must be between 0 and 1000")
    if any(limit is not None and (type(limit) is not int or limit < 0)
           for limit in (total_limit, file_limit)):
        raise AssetSizeError("Budgets must be nonnegative integers")
    extension_limits = extension_limits or {}
    totals = {}
    for asset in entries:
        row = totals.setdefault(asset["extension"], {"files": 0, "bytes": 0})
        row["files"] += 1
        row["bytes"] += asset["bytes"]
    total = sum(asset["bytes"] for asset in entries)
    violations = []
    if total_limit is not None and total > total_limit:
        violations.append({"rule": "total", "actual": total, "limit": total_limit})
    for extension in sorted(extension_limits):
        actual = totals.get(extension, {}).get("bytes", 0)
        if actual > extension_limits[extension]:
            violations.append({"rule": "extension", "extension": extension,
                               "actual": actual, "limit": extension_limits[extension]})
    if file_limit is not None:
        for asset in entries:
            if asset["bytes"] > file_limit:
                violations.append({"rule": "file", "path": asset["path"],
                                   "actual": asset["bytes"], "limit": file_limit})
    return {
        "file_count": len(entries),
        "total_bytes": total,
        "by_extension": [{"extension": ext, **totals[ext]} for ext in sorted(totals)],
        "largest_files": [{"path": item["path"], "bytes": item["bytes"]}
                          for item in nsmallest(top, entries, key=lambda x: (-x["bytes"], x["path"]))],
        "violations": violations,
    }


def _nonnegative(value):
    if not value.isascii() or not value.isdecimal():
        raise argparse.ArgumentTypeError("Expected a nonnegative integer in bytes")
    return int(value)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("project", type=Path, help="Directory containing project.godot")
    parser.add_argument("--format", choices=("text", "json"), default="text")
    parser.add_argument("--top", type=_nonnegative, default=10, help="Largest files to display (0-1000)")
    parser.add_argument("--total-limit", type=_nonnegative, help="Maximum combined asset bytes")
    parser.add_argument("--file-limit", type=_nonnegative, help="Maximum bytes in a single file")
    parser.add_argument("--extension-limit", action="append", default=[], metavar="EXT=BYTES",
                        help="Maximum combined bytes for an extension (repeatable)")
    args = parser.parse_args(argv)
    try:
        limits = parse_extension_limits(args.extension_limit)
        report = build_report(scan_project(args.project), args.top, args.total_limit,
                              args.file_limit, limits)
    except (AssetSizeError, OSError) as error:
        print("asset_size_map: {}".format(error), file=sys.stderr)
        return 2
    if args.format == "json":
        print(json.dumps(report, ensure_ascii=False, sort_keys=True))
    else:
        print("{} assets, {} bytes total".format(report["file_count"], report["total_bytes"]))
        for group in report["by_extension"]:
            print("  {}: {} files, {} bytes".format(group["extension"], group["files"], group["bytes"]))
        print("Largest assets:")
        for asset in report["largest_files"]:
            print("  {} bytes  {}".format(asset["bytes"], asset["path"]))
        for violation in report["violations"]:
            target = violation.get("path", violation.get("extension", "project"))
            print("BUDGET {} {}: {} > {} bytes".format(
                violation["rule"], target, violation["actual"], violation["limit"]))
    return 1 if report["violations"] else 0


if __name__ == "__main__":
    sys.exit(main())
