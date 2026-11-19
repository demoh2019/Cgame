#!/usr/bin/env python3
"""Static validation for Godot project resource paths (Python stdlib only).

This is intentionally conservative: it validates explicit res:// paths in scene,
resource and project settings, and constant load()/preload() script calls. It does
not attempt to execute scripts, parse UIDs, or validate imported binary resources.
"""

from __future__ import annotations

import argparse
import fnmatch
import json
import os
import re
import sys
from collections import defaultdict
from dataclasses import asdict, dataclass
from pathlib import Path, PurePosixPath
from typing import Iterable

TEXT_EXTENSIONS = frozenset({".tscn", ".tres", ".gd", ".gdshader", ".shader", ".cs", ".gdextension"})
SKIP_DIRS = frozenset({".git", ".godot", ".svn", "__pycache__", ".hg"})
SETTING_REF_RE = re.compile(r"\b(?:path|main_scene|icon)\s*=\s*(?P<quote>[\"'])(?P<uri>res://[^\"'\r\n]*)(?P=quote)")
LOAD_REF_RE = re.compile(r"\b(?:preload|load)\s*\(\s*(?P<quote>[\"'])(?P<uri>res://[^\"'\r\n]*)(?P=quote)(?=\s*[,\)])")


@dataclass(frozen=True, order=True)
class Finding:
    severity: str
    code: str
    path: str
    line: int
    message: str
    reference: str = ""

    def to_dict(self) -> dict:
        return asdict(self)


@dataclass
class AuditReport:
    root: str
    files: int
    references: int
    findings: list[Finding]
    graph: dict[str, list[str]]

    def to_dict(self) -> dict:
        return {
            "root": self.root,
            "summary": {
                "files": self.files,
                "references": self.references,
                "errors": sum(f.severity == "error" for f in self.findings),
                "warnings": sum(f.severity == "warning" for f in self.findings),
            },
            "findings": [f.to_dict() for f in self.findings],
            "graph": self.graph,
        }


def _is_excluded(relative: str, patterns: Iterable[str]) -> bool:
    return any(fnmatch.fnmatchcase(relative, pattern) or fnmatch.fnmatchcase(relative + "/", pattern) for pattern in patterns)


def list_project_files(root: Path, exclude: Iterable[str] = ()) -> list[str]:
    """Return project-relative paths using POSIX separators, without following dirs links."""
    root = root.resolve()
    excludes = tuple(exclude)
    def reject_scan_failure(error: OSError) -> None:
        # By default os.walk silently ignores unreadable directories. A partial
        # inventory could incorrectly report missing dependencies as valid.
        raise ValueError(f"Cannot enumerate all project files: {error}")

    result: list[str] = []
    for directory, dirs, files in os.walk(root, followlinks=False, onerror=reject_scan_failure):
        relative_dir = Path(directory).relative_to(root).as_posix()
        dirs[:] = sorted(name for name in dirs if name not in SKIP_DIRS and not _is_excluded(
            name if relative_dir == "." else relative_dir + "/" + name, excludes))
        for name in sorted(files):
            relative = (Path(directory) / name).relative_to(root).as_posix()
            if not _is_excluded(relative, excludes):
                result.append(relative)
    return sorted(result)


def _strip_comments(line: str, extension: str) -> str:
    """Drop comments outside quoted strings, preserving character offsets."""
    marker = "//" if extension in {".cs", ".gdshader", ".shader"} else "#"
    quote = ""
    escaped = False
    index = 0
    while index < len(line):
        ch = line[index]
        if quote:
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == quote:
                quote = ""
        elif ch in ("'", '"'):
            quote = ch
        elif line.startswith(marker, index):
            return line[:index]
        index += 1
    return line


def _outside_quotes(line: str, offset: int) -> bool:
    """True for code positions, not positions embedded in a string literal."""
    quote = ""
    escaped = False
    for ch in line[:offset]:
        if quote:
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == quote:
                quote = ""
        elif ch in ("'", '"'):
            quote = ch
    return not quote


def extract_references(content: str, extension: str) -> list[tuple[int, str]]:
    """Return literal resource references with original source line numbers."""
    refs: list[tuple[int, str]] = []
    for number, raw in enumerate(content.splitlines(), 1):
        line = _strip_comments(raw, extension)
        expressions = [LOAD_REF_RE]
        if extension in {".tscn", ".tres", ".gdextension", ".godot"}:
            expressions.append(SETTING_REF_RE)
        found = set()
        for expr in expressions:
            for match in expr.finditer(line):
                if _outside_quotes(line, match.start()):
                    found.add(match.group("uri"))
        refs.extend((number, uri) for uri in sorted(found))
    return refs


def _validate_uri(uri: str) -> str | None:
    if not uri.startswith("res://"):
        return "URI must begin with res://."
    name = uri[6:]
    if not name or "\\" in name or "\x00" in name:
        return "Resource path is empty or uses a forbidden character."
    if name.startswith("/") or any(part in {"", ".", ".."} for part in name.split("/")):
        return "Resource path contains an empty, current or parent segment."
    if ":" in name:
        return "Resource path contains a colon; external paths are not permitted."
    return None


def _resource_nodes(files: list[str]) -> set[str]:
    return {path for path in files if Path(path).suffix.lower() in TEXT_EXTENSIONS}


def find_cycles(graph: dict[str, list[str]]) -> list[tuple[str, ...]]:
    """Strongly connected components of size >1, without recursion depth limits."""
    # Iterative Kosaraju keeps huge script dependency graphs from overflowing stack.
    nodes = set(graph)
    for destinations in graph.values():
        nodes.update(destinations)
    visited: set[str] = set()
    order: list[str] = []
    for start in sorted(nodes):
        if start in visited:
            continue
        # Discover each node exactly once. The old stack queued the same
        # not-yet-visited child repeatedly in dense graphs (up to O(E) frames).
        # Component members and the final cycle list are sorted below, so
        # traversal order of existing adjacency lists does not affect output.
        visited.add(start)
        stack = [(start, iter(graph.get(start, ())))]
        while stack:
            node, neighbors = stack[-1]
            try:
                child = next(neighbors)
            except StopIteration:
                order.append(node)
                stack.pop()
                continue
            if child not in visited:
                visited.add(child)
                stack.append((child, iter(graph.get(child, ()))))
    reversed_graph: dict[str, list[str]] = defaultdict(list)
    for source, destinations in graph.items():
        for destination in destinations:
            reversed_graph[destination].append(source)
    assigned: set[str] = set()
    cycles: list[tuple[str, ...]] = []
    for start in reversed(order):
        if start in assigned:
            continue
        component: list[str] = []
        todo = [start]
        assigned.add(start)
        while todo:
            node = todo.pop()
            component.append(node)
            for parent in reversed_graph.get(node, ()):
                if parent not in assigned:
                    assigned.add(parent)
                    todo.append(parent)
        if len(component) > 1:
            cycles.append(tuple(sorted(component)))
    return sorted(cycles)


def audit_project(root: Path, exclude: Iterable[str] = (), check_cycles: bool = True) -> AuditReport:
    root = Path(root).expanduser().resolve()
    if not root.is_dir():
        raise ValueError(f"Project directory does not exist: {root}")
    if not (root / "project.godot").is_file():
        raise ValueError(f"No project.godot found at: {root}")
    paths = list_project_files(root, exclude)
    actual_paths = set(paths)
    casefolded: dict[str, list[str]] = defaultdict(list)
    for relative in paths:
        casefolded[relative.casefold()].append(relative)
    findings: list[Finding] = []
    for members in casefolded.values():
        if len(members) > 1:
            for member in sorted(members):
                findings.append(Finding("error", "CASE_COLLISION", member, 0, "Collides with another asset on case-insensitive filesystems: " + ", ".join(sorted(members))))

    graph: dict[str, set[str]] = defaultdict(set)
    reference_count = 0
    nodes = _resource_nodes(paths)
    nodes.add("project.godot")
    for relative in paths:
        extension = Path(relative).suffix.lower()
        if extension not in TEXT_EXTENSIONS and relative != "project.godot":
            continue
        source = root / relative
        try:
            text = source.read_text(encoding="utf-8-sig")
        except (UnicodeError, OSError) as exc:
            findings.append(Finding("warning", "UNREADABLE_TEXT", relative, 0, f"Unable to read text resource: {type(exc).__name__}"))
            continue
        for line, uri in extract_references(text, ".godot" if relative == "project.godot" else extension):
            reference_count += 1
            error = _validate_uri(uri)
            if error is not None:
                findings.append(Finding("error", "INVALID_URI", relative, line, error, uri))
                continue
            destination = uri[6:]
            try:
                resolved = (root / PurePosixPath(destination)).resolve()
            except (OSError, RuntimeError):
                findings.append(Finding("error", "UNRESOLVABLE_RESOURCE", relative, line, "Resource reference cannot be resolved (e.g. a symlink loop).", uri))
                continue
            if not resolved.is_relative_to(root):
                findings.append(Finding("error", "OUTSIDE_PROJECT", relative, line, "Resource reference escapes the project root.", uri))
                continue
            if destination not in actual_paths or not resolved.is_file():
                alternatives = casefolded.get(destination.casefold(), ())
                if alternatives:
                    findings.append(Finding("error", "CASE_MISMATCH", relative, line, "Resource exists with different capitalization: " + ", ".join(sorted(alternatives)), uri))
                else:
                    findings.append(Finding("error", "MISSING_RESOURCE", relative, line, "Resource path does not exist.", uri))
                continue
            if destination in nodes:
                graph[relative].add(destination)
    ordered_graph = {node: sorted(graph.get(node, ())) for node in sorted(nodes)}
    if check_cycles:
        for group in find_cycles(ordered_graph):
            findings.append(Finding("warning", "DEPENDENCY_CYCLE", group[0], 0, "Resource dependency cycle: " + " -> ".join((*group, group[0]))))
    return AuditReport(str(root), len(paths), reference_count, sorted(findings), ordered_graph)


def _render_text(report: AuditReport) -> str:
    data = report.to_dict()
    lines = [f"Asset audit: {report.root}", f"Files: {report.files}, references: {report.references}, errors: {data['summary']['errors']}, warnings: {data['summary']['warnings']}"]
    for finding in report.findings:
        where = f"{finding.path}:{finding.line}" if finding.line else finding.path
        lines.append(f"{where}: {finding.severity.upper()} {finding.code}: {finding.message}" + (f" [{finding.reference}]" if finding.reference else ""))
    return "\n".join(lines)


def _render_github(report: AuditReport) -> str:
    """Format GitHub Actions workflow commands without allowing newline injection."""
    def escape(value: str, property_value: bool = False) -> str:
        value = value.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
        if property_value:
            value = value.replace(":", "%3A").replace(",", "%2C")
        return value

    return "\n".join(
        f"::{finding.severity} file={escape(finding.path, True)},line={finding.line or 1},title={escape(finding.code, True)}::{escape(finding.message + (' [' + finding.reference + ']' if finding.reference else ''))}"
        for finding in report.findings
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Audit explicit res:// dependencies in a Godot project")
    parser.add_argument("root", type=Path, help="Directory containing project.godot")
    parser.add_argument("--format", choices=("text", "json", "github"), default="text")
    parser.add_argument("--exclude", action="append", default=[], metavar="GLOB", help="Exclude project-relative paths (repeatable)")
    parser.add_argument("--no-cycles", action="store_true", help="Disable static dependency cycle warnings")
    parser.add_argument("--fail-on", choices=("none", "warning", "error"), default="error")
    parser.add_argument("--output", type=Path, help="Write the result to a file instead of stdout")
    args = parser.parse_args(argv)
    try:
        report = audit_project(args.root, args.exclude, not args.no_cycles)
    except ValueError as exc:
        parser.error(str(exc))
    result = (json.dumps(report.to_dict(), ensure_ascii=False, indent=2) if args.format == "json" else
              _render_github(report) if args.format == "github" else _render_text(report))
    if args.output:
        args.output.write_text(result + "\n", encoding="utf-8")
    else:
        print(result)
    has_errors = any(f.severity == "error" for f in report.findings)
    has_warnings = any(f.severity == "warning" for f in report.findings)
    return int(args.fail_on == "error" and has_errors or args.fail_on == "warning" and (has_warnings or has_errors))


if __name__ == "__main__":
    sys.exit(main())
