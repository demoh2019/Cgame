"""Bounded, structured Godot log diagnostics for AI Game Builder repair review.

The parser never runs code, opens source files or sends diagnostics to a model.
Raw log messages are untrusted text; consumers must not treat them as commands.
"""

from __future__ import annotations

import io
from pathlib import Path
import re
from typing import BinaryIO

MAX_DIAGNOSTICS = 30
MAX_LINE_BYTES = 4096
MAX_MESSAGE_CHARS = 500
ERROR_LINE = re.compile(r"^\s*(?:SCRIPT ERROR|ERROR|Parse Error)\s*:", re.IGNORECASE)
WARNING_LINE = re.compile(r"^\s*WARNING\s*:", re.IGNORECASE)
ANSI_ESCAPE = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")
# The first path group is bounded and revalidated to avoid misleading model hints.
RESOURCE_LINE = re.compile(
    r"(?P<resource>res://[^\s()\[\]{}<>\"']{1,240}?):"
    r"(?P<line>[1-9][0-9]{0,6})(?::(?P<column>[1-9][0-9]{0,6}))?"
    r"(?=$|[\s),\]}])"
)


def _limited_lines(stream: BinaryIO):
    """Read the entire stream with bounded per-line memory (even without newlines)."""
    while chunk := stream.readline(MAX_LINE_BYTES + 1):
        if len(chunk) <= MAX_LINE_BYTES or chunk.endswith(b"\n"):
            yield chunk[:MAX_LINE_BYTES]
            continue
        # Retain the beginning of an oversized line and discard its tail.
        prefix = chunk[:MAX_LINE_BYTES]
        while chunk and not chunk.endswith(b"\n"):
            chunk = stream.readline(MAX_LINE_BYTES + 1)
        yield prefix


def _location(text: str) -> dict[str, object]:
    for match in RESOURCE_LINE.finditer(text):
        path = match.group("resource")
        parts = path.removeprefix("res://").split("/")
        if (not parts or any(not part or part in (".", "..") for part in parts)
                or "\\" in path or ":" in path[6:] or any(ord(char) < 32 for char in path)):
            continue
        location: dict[str, object] = {"resource": path, "line": int(match.group("line"))}
        if match.group("column"):
            location["column"] = int(match.group("column"))
        return location
    return {}


def scan_log(stream: BinaryIO, stage: Path) -> dict[str, object]:
    """Extract all errors reliably, even when the user-facing log is truncated.

    Keep at most 30 error and 30 warning messages and structured records.
    Return total counts so automation can detect omitted diagnostics.
    """
    stream.seek(0)
    errors: list[str] = []
    warnings: list[str] = []
    diagnostics: list[dict[str, object]] = []
    error_count = warning_count = 0
    last_record: dict[str, object] | None = None
    for raw in _limited_lines(stream):
        line = ANSI_ESCAPE.sub("", raw.decode("utf-8", "replace"))
        line = line.replace(str(stage), "<STAGED_PROJECT>").rstrip("\r\n")[:MAX_MESSAGE_CHARS]
        if ERROR_LINE.match(line):
            error_count += 1
            last_record = None
            if len(errors) < MAX_DIAGNOSTICS:
                errors.append(line)
                entry: dict[str, object] = {"severity": "error", "message": line}
                entry.update(_location(line))
                diagnostics.append(entry)
                last_record = entry
        elif WARNING_LINE.match(line):
            warning_count += 1
            last_record = None
            if len(warnings) < MAX_DIAGNOSTICS:
                warnings.append(line)
                entry = {"severity": "warning", "message": line}
                entry.update(_location(line))
                diagnostics.append(entry)
                last_record = entry
        elif last_record is not None and line.strip().lower().startswith("at:"):
            # Godot commonly prints a location on the line after a diagnostic.
            if "resource" not in last_record:
                last_record.update(_location(line))
            last_record = None
        elif line.strip():
            last_record = None
    return {"errors": errors, "warnings": warnings, "diagnostics": diagnostics,
            "error_count": error_count, "warning_count": warning_count}


def scan_text(text: str, stage: Path) -> dict[str, object]:
    return scan_log(io.BytesIO(text.encode("utf-8", "replace")), stage)
