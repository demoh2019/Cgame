#!/usr/bin/env python3
"""Turn a failed Godot smoke report into a bounded, review-first AI repair context.

This tool does not call a model, edit files, execute scripts, or upload data.
The caller must explicitly select any source files allowed into the context.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import stat
import sys

SCHEMA = "cgame.ai_repair_context.v1"
MAX_REPORT_BYTES = 1024 * 1024
MAX_DIAGNOSTICS = 30
MAX_SOURCE_FILES = 4
MAX_SOURCE_BYTES = 32 * 1024
MAX_EXCERPT_CHARS = 1200
MAX_LINE = 500
SOURCE_TYPES = frozenset({".gd", ".tscn", ".tres", ".gdshader"})
REF = re.compile(r'(?:res://|<STAGED_PROJECT>/)(?P<file>[^\s:"\'()<>]+)(?::(?P<line>[0-9]{1,6}))?')


class RepairContextError(ValueError):
    """The input is malformed, unsafe, or exceeds the privacy budget."""


def _safe_source(root: Path, uri: str) -> Path:
    if not uri.startswith("res://"):
        raise RepairContextError("Source must be a res:// path")
    rel = uri[6:]
    parts = rel.split("/")
    if (not rel or len(rel) > 512 or rel.startswith("/") or "\\" in rel or ":" in rel
            or any(p in ("", ".", "..") or p.startswith(".") for p in parts)
            or Path(rel).suffix.lower() not in SOURCE_TYPES):
        raise RepairContextError("Unsafe source path")
    result = root
    for part in parts:
        result = result / part
        if result.is_symlink():
            raise RepairContextError("Symlinked source path")
    return result


def _hint_category(message: str) -> str:
    value = message.casefold()
    if "parse error" in value or "syntax error" in value:
        return "syntax"
    if "not found" in value or "failed loading" in value or "can't open" in value:
        return "missing_resource"
    if "script error" in value or "invalid call" in value:
        return "runtime"
    if "import" in value:
        return "import"
    return "other"


def _target(message: str) -> tuple[str | None, int | None]:
    match = REF.search(message)
    if not match:
        return None, None
    raw = match.group("file").rstrip(".,;]")
    uri = "res://" + raw
    # Do not return a potentially malicious or out-of-project path.
    try:
        _safe_source(Path("/unused"), uri)
    except RepairContextError:
        return None, None
    line = int(match.group("line")) if match.group("line") else None
    return uri, line if line and line <= 100000 else None


def _excerpt(root: Path, uri: str, line: int) -> dict | None:
    path = _safe_source(root, uri)
    try:
        before = path.stat()
        if not stat.S_ISREG(before.st_mode) or before.st_size > MAX_SOURCE_BYTES:
            return None
        flags = os.O_RDONLY | getattr(os, "O_BINARY", 0) | getattr(os, "O_NOFOLLOW", 0)
        with os.fdopen(os.open(path, flags), "rb") as handle:
            raw = handle.read(MAX_SOURCE_BYTES + 1)
            after = os.fstat(handle.fileno())
        if (len(raw) > MAX_SOURCE_BYTES or b"\0" in raw
                or (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns)
                != (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns)):
            return None
        lines = raw.decode("utf-8-sig").splitlines()
    except (OSError, UnicodeError):
        return None
    if not 1 <= line <= len(lines):
        return None
    start, end = max(1, line - 2), min(len(lines), line + 2)
    snippet = "\n".join(f"{i}: {lines[i - 1]}" for i in range(start, end + 1))
    return {"line_start": start, "line_end": end, "text": snippet[:MAX_EXCERPT_CHARS]}


def build_context(report: dict, root: Path, allow_sources: tuple[str, ...] = ()) -> dict:
    """Extract diagnostics from a *failed* v1 smoke report without implicit file reads."""
    if (not isinstance(report, dict) or type(report.get("ok")) is not bool
            or report.get("format") != 1 or not isinstance(report.get("checks"), list)
            or not 1 <= len(report["checks"]) <= 10):
        raise RepairContextError("Invalid Godot smoke report")
    if report["ok"]:
        raise RepairContextError("Report succeeded; no repair needed")
    root = Path(root).absolute()
    if (root.is_symlink() or not root.is_dir() or not (root / "project.godot").is_file()
            or (root / "project.godot").is_symlink()):
        raise RepairContextError("Expected a regular Godot project root")
    allowed = set(allow_sources)
    if len(allowed) > MAX_SOURCE_FILES:
        raise RepairContextError("At most four source files may be selected")
    for uri in allowed:
        _safe_source(root, uri)
    hints = []
    error_total = 0
    warning_total = 0
    for stage in report["checks"]:
        if (not isinstance(stage, dict) or stage.get("name") not in ("import", "game")
                or type(stage.get("ok")) is not bool
                or not isinstance(stage.get("errors"), list)
                or not isinstance(stage.get("warnings"), list)):
            raise RepairContextError("Invalid Godot check")
        errors, warnings = stage["errors"], stage["warnings"]
        if (len(errors) > 100 or len(warnings) > 100
                or not all(isinstance(s, str) for s in errors + warnings)):
            raise RepairContextError("Invalid diagnostic list")
        ec = stage.get("error_count", len(errors))
        wc = stage.get("warning_count", len(warnings))
        if (type(ec) is not int or ec < len(errors) or type(wc) is not int or wc < len(warnings)):
            raise RepairContextError("Invalid diagnostic count")
        error_total += ec
        warning_total += wc
        if not stage["ok"] and not errors:
            hints.append({"stage": stage["name"], "kind": "other",
                          "message": "Godot stage failed without a captured diagnostic",
                          "path": None, "line": None})
        for message in errors:
            if len(hints) >= MAX_DIAGNOSTICS:
                break
            uri, line = _target(message)
            hint = {"stage": stage["name"], "kind": _hint_category(message),
                    "message": message[:MAX_LINE], "path": uri, "line": line}
            if uri in allowed and line is not None:
                excerpt = _excerpt(root, uri, line)
                if excerpt:
                    hint["source_excerpt"] = excerpt
            hints.append(hint)
    if not any(not s["ok"] for s in report["checks"]):
        raise RepairContextError("Inconsistent report: all stages succeeded")
    return {"schema": SCHEMA, "status": "needs_review", "requires_approval": True,
            "diagnostics_untrusted": True, "source_opt_in": bool(allowed),
            "summary": {"errors": error_total, "warnings": warning_total,
                        "hints": len(hints), "truncated": error_total > len(hints)},
            "hints": hints}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("project", type=Path)
    parser.add_argument("--report", required=True, type=Path, help="JSON report from ai_project_smoke.py")
    parser.add_argument("--allow-source", action="append", default=[], metavar="res://FILE",
                        help="Explicitly include a short excerpt around an error line (max 4)")
    args = parser.parse_args(argv)
    try:
        if args.report.stat().st_size > MAX_REPORT_BYTES:
            raise RepairContextError("Report exceeds 1 MiB")
        report = json.loads(args.report.read_text(encoding="utf-8"))
        result = build_context(report, args.project, tuple(args.allow_source))
    except (OSError, UnicodeError, ValueError) as exc:
        print(f"AI repair context: {exc}", file=sys.stderr)
        return 2
    print(json.dumps(result, ensure_ascii=False, sort_keys=True, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
