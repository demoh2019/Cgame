#!/usr/bin/env python3
"""Audit path portability and static res:// references in a Godot project.

Uses only Python's standard library; does not import the Godot editor or mutate
project files. Suitable for CI before an expensive asset import/build.
"""

from __future__ import annotations

import argparse
from dataclasses import asdict, dataclass, field
import fnmatch
import json
import os
from pathlib import Path, PurePosixPath
import re
import sys
import unicodedata

IGNORED_DIRS = frozenset({".git", ".godot", ".import", ".venv", "venv", "node_modules", "__pycache__"})
TEXT_EXTENSIONS = frozenset({".gd", ".tscn", ".tres", ".godot", ".gdshader", ".gdshaderinc", ".cs", ".cfg", ".shader", ".escn", ".json"})
# Only inspect complete, quoted string literals; text in comments is ignored.
QUOTED_STRING = re.compile(r"(?P<quote>['\"])(?P<value>(?:\\.|(?!(?P=quote)).)*)(?P=quote)")


def portability_key(path: str) -> str:
    """Approximate case-insensitive / Unicode-normalizing target filesystems."""
    return unicodedata.normalize("NFC", path).casefold()


@dataclass(frozen=True)
class Finding:
    severity: str
    code: str
    source: str
    line: int
    message: str
    reference: str = ""

    def sort_key(self) -> tuple[str, int, str, str]:
        return self.source, self.line, self.code, self.reference


@dataclass
class Report:
    files_scanned: int
    references_checked: int
    findings: list[Finding]
    dependencies: dict[str, list[str]] = field(default_factory=dict)

    def to_dict(self) -> dict:
        return {
            "summary": {
                "files_scanned": self.files_scanned,
                "references_checked": self.references_checked,
                "errors": sum(item.severity == "error" for item in self.findings),
                "warnings": sum(item.severity == "warning" for item in self.findings),
            },
            "findings": [asdict(item) for item in self.findings],
            "dependencies": self.dependencies,
        }

    @property
    def errors(self) -> int:
        return sum(item.severity == "error" for item in self.findings)

    @property
    def warnings(self) -> int:
        return sum(item.severity == "warning" for item in self.findings)


def _matches_exclusion(relative: str, patterns: tuple[str, ...]) -> bool:
    return any(fnmatch.fnmatch(relative, pattern) or fnmatch.fnmatch(PurePosixPath(relative).name, pattern)
               for pattern in patterns)


def _iterate_entries(root: Path, patterns: tuple[str, ...]):
    """List entries deterministically and prune generated/vendor directories."""
    def fail_walk(error: OSError) -> None:
        # An inaccessible subtree must not silently produce a clean audit.
        raise ValueError(f"Cannot enumerate project files: {error}") from error

    for base, dirs, files in os.walk(root, topdown=True, followlinks=False, onerror=fail_walk):
        here = Path(base)
        dirs[:] = sorted(d for d in dirs if d not in IGNORED_DIRS
                         and not _matches_exclusion((here / d).relative_to(root).as_posix(), patterns))
        for name in sorted(dirs + files):
            path = here / name
            relative = path.relative_to(root).as_posix()
            if not _matches_exclusion(relative, patterns):
                yield path, relative


def _strip_inline_comment(line: str, extension: str) -> str:
    """Remove supported line comments without truncating quoted literals."""
    if extension == ".gd":
        marker = "#"
    elif extension in {".cs", ".gdshader", ".gdshaderinc", ".shader"}:
        marker = "//"
    else:
        return line

    quote = None
    escaped = False
    i = 0
    while i < len(line):
        char = line[i]
        if quote is not None:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == quote:
                quote = None
        elif char in ("'", '"'):
            quote = char
        elif line.startswith(marker, i):
            return line[:i]
        i += 1
    return line


def _iter_static_references(text: str, extension: str):
    """Yield (line_number, res_target) from literal resource paths, not comments."""
    for lineno, line in enumerate(text.splitlines(), start=1):
        stripped = line.lstrip()
        if stripped.startswith("<!--"):
            continue
        # Shader #include "res://..." is an actual reference, not a comment.
        if stripped.startswith("#") and not stripped.startswith("#include"):
            continue
        if extension in {".gd", ".cs"} and stripped.startswith("//"):
            continue
        for match in QUOTED_STRING.finditer(_strip_inline_comment(line, extension)):
            value = match.group("value")
            if value.startswith("res://"):
                yield lineno, value[6:]


def find_dependency_cycles(graph: dict[str, set[str]]) -> list[tuple[str, ...]]:
    """Return strongly connected components with cycles, in deterministic order.

    Iterative Kosaraju avoids recursion errors on large projects. A self-loop
    counts as a cycle. Unconnected files and acyclic components are omitted.
    """
    nodes = set(graph)
    for children in graph.values():
        nodes.update(children)
    forward = {node: tuple(sorted(graph.get(node, ()))) for node in nodes}
    reverse = {node: [] for node in nodes}
    for source, destinations in forward.items():
        for destination in destinations:
            reverse[destination].append(source)
    for parents in reverse.values():
        parents.sort()

    visited: set[str] = set()
    finished: list[str] = []
    for start in sorted(nodes):
        if start in visited:
            continue
        visited.add(start)
        stack = [(start, iter(forward[start]))]
        while stack:
            node, children = stack[-1]
            child = next(children, None)
            if child is None:
                finished.append(node)
                stack.pop()
            elif child not in visited:
                visited.add(child)
                stack.append((child, iter(forward[child])))

    assigned: set[str] = set()
    cycles: list[tuple[str, ...]] = []
    for start in reversed(finished):
        if start in assigned:
            continue
        component = []
        todo = [start]
        assigned.add(start)
        while todo:
            node = todo.pop()
            component.append(node)
            for parent in reverse[node]:
                if parent not in assigned:
                    assigned.add(parent)
                    todo.append(parent)
        if len(component) > 1 or (len(component) == 1 and start in forward[start]):
            cycles.append(tuple(sorted(component)))
    return sorted(cycles)


def scan_project(root: Path, max_text_bytes: int = 8 * 1024 * 1024,
                 exclude: tuple[str, ...] = (), check_cycles: bool = True) -> Report:
    """Return deterministic errors/warnings for static Godot resource references.

    Does not resolve uid://, dynamic string concatenations, or external imports.
    """
    root = Path(root).resolve()
    if not root.is_dir():
        raise ValueError(f"Project root is not a directory: {root}")
    if max_text_bytes < 1:
        raise ValueError("max_text_bytes must be at least 1")

    entries = list(_iterate_entries(root, exclude))
    findings: list[Finding] = []
    index: dict[str, list[str]] = {}
    for path, rel in entries:
        if path.is_symlink():
            try:
                resolved_link = path.resolve(strict=True)
            except (OSError, RuntimeError):
                findings.append(Finding("error", "UNRESOLVABLE_SYMLINK", rel, 0,
                                        "Symlink target is missing or contains a loop."))
                continue
            try:
                resolved_link.relative_to(root)
            except ValueError:
                findings.append(Finding("warning", "EXTERNAL_SYMLINK", rel, 0,
                                        "Symlink targets a location outside the project."))
                continue
        index.setdefault(portability_key(rel), []).append(rel)

    for names in index.values():
        if len(names) > 1:
            for name in sorted(names):
                findings.append(Finding("error", "CASE_COLLISION", name, 0,
                                        "Different paths collide on case-insensitive or Unicode-normalizing filesystems: "
                                        + ", ".join(sorted(names))))

    scan_sources = {rel for path, rel in entries if not path.is_symlink()
                    and path.is_file() and path.suffix.lower() in TEXT_EXTENSIONS}
    dependencies: dict[str, set[str]] = {}
    files_scanned = 0
    references_checked = 0
    for path, rel in entries:
        if path.is_symlink() or not path.is_file() or path.suffix.lower() not in TEXT_EXTENSIONS:
            continue
        files_scanned += 1
        try:
            size = path.stat().st_size
            if size > max_text_bytes:
                findings.append(Finding("warning", "FILE_TOO_LARGE", rel, 0,
                                        f"Skipped text file larger than {max_text_bytes} bytes."))
                continue
            text = path.read_text(encoding="utf-8")
        except UnicodeError:
            findings.append(Finding("warning", "INVALID_UTF8", rel, 0,
                                    "Skipped text resource that is not valid UTF-8."))
            continue
        except OSError as exc:
            findings.append(Finding("error", "READ_FAILED", rel, 0, f"Unable to read file: {exc}"))
            continue

        for lineno, target in _iter_static_references(text, path.suffix.lower()):
            references_checked += 1
            original = "res://" + target
            if not target:
                findings.append(Finding("error", "EMPTY_RESOURCE_PATH", rel, lineno,
                                        "Empty res:// path cannot identify a resource.", original))
                continue
            if "\\" in target:
                findings.append(Finding("error", "INVALID_SEPARATOR", rel, lineno,
                                        "Resource paths must use '/' separators.", original))
                continue
            parts = PurePosixPath(target).parts
            if target.startswith("/") or ".." in parts:
                findings.append(Finding("error", "INVALID_RESOURCE_PATH", rel, lineno,
                                        "Absolute paths and parent traversal are not allowed in res:// references.", original))
                continue
            if parts and parts[0] in {".godot", ".import"}:
                # Godot generates these files when importing assets.
                continue

            candidate = root.joinpath(*parts)
            try:
                resolved_candidate = candidate.resolve()
            except (OSError, RuntimeError):
                findings.append(Finding("error", "UNRESOLVABLE_RESOURCE", rel, lineno,
                                        "Resource path contains an unresolvable symlink.", original))
                continue
            try:
                resolved_candidate.relative_to(root)
            except ValueError:
                findings.append(Finding("error", "RESOURCE_OUTSIDE_PROJECT", rel, lineno,
                                        "Resource reference resolves outside the project.", original))
                continue
            if candidate.exists():
                if candidate.is_dir():
                    findings.append(Finding("error", "RESOURCE_IS_DIRECTORY", rel, lineno,
                                            "Resource reference points to a directory, not a file.", original))
                elif candidate.is_file():
                    target_relative = resolved_candidate.relative_to(root).as_posix()
                    if target_relative in scan_sources:
                        dependencies.setdefault(rel, set()).add(target_relative)
                continue
            possible = index.get(portability_key(PurePosixPath(target).as_posix()), [])
            if len(possible) == 1 and possible[0] != PurePosixPath(target).as_posix():
                findings.append(Finding("error", "CASE_MISMATCH", rel, lineno,
                                        f"Resource path case does not match existing file: {possible[0]}", original))
            else:
                findings.append(Finding("error", "MISSING_RESOURCE", rel, lineno,
                                        "Resource path does not exist in the project.", original))

    if check_cycles:
        for component in find_dependency_cycles(dependencies):
            sample = ", ".join(component[:8])
            if len(component) > 8:
                sample += f", ... ({len(component)} files total)"
            findings.append(Finding("warning", "DEPENDENCY_CYCLE", component[0], 0,
                                    f"Static resource dependency cycle: {sample}"))

    findings.sort(key=Finding.sort_key)
    ordered_dependencies = {name: sorted(children) for name, children in sorted(dependencies.items())}
    return Report(files_scanned, references_checked, findings, ordered_dependencies)


def _escape_github_data(value: str) -> str:
    """Escape workflow-command data to avoid injected CI annotations."""
    return value.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


def _escape_github_property(value: str) -> str:
    return _escape_github_data(value).replace(":", "%3A").replace(",", "%2C")


def _format_github_finding(finding: Finding) -> str:
    level = "error" if finding.severity == "error" else "warning"
    props = ["file=" + _escape_github_property(finding.source)]
    if finding.line > 0:
        props.append("line=" + str(finding.line))
    props.append("title=" + _escape_github_property(finding.code))
    message = finding.message
    if finding.reference:
        message += " [" + finding.reference + "]"
    return f"::{level} {','.join(props)}::{_escape_github_data(message)}"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", nargs="?", default=".", type=Path, help="Godot project directory (default: current directory)")
    parser.add_argument("--format", choices=("text", "json", "github"), default="text", help="Output format")
    parser.add_argument("--exclude", action="append", default=[], metavar="GLOB",
                        help="Exclude matching relative project paths (repeatable)")
    parser.add_argument("--max-text-bytes", type=int, default=8 * 1024 * 1024,
                        help="Maximum bytes to read from a text resource")
    parser.add_argument("--fail-on-warning", action="store_true", help="Return nonzero on warnings, too")
    parser.add_argument("--no-cycles", action="store_true",
                        help="Skip static resource dependency cycle diagnostics")
    args = parser.parse_args(argv)
    try:
        report = scan_project(args.root, args.max_text_bytes, tuple(args.exclude),
                              check_cycles=not args.no_cycles)
    except ValueError as exc:
        print(f"Asset audit: {exc}", file=sys.stderr)
        return 2

    if args.format == "json":
        print(json.dumps(report.to_dict(), indent=2, ensure_ascii=False, sort_keys=True))
    elif args.format == "github":
        for finding in report.findings:
            print(_format_github_finding(finding))
        print(f"Asset audit: {report.errors} errors, {report.warnings} warnings "
              f"across {report.files_scanned} files.")
    else:
        for finding in report.findings:
            location = f"{finding.source}:{finding.line}" if finding.line else finding.source
            print(f"{location}: {finding.severity}: {finding.code}: {finding.message}")
        print(f"Scanned {report.files_scanned} text files, checked {report.references_checked} references: "
              f"{report.errors} errors, {report.warnings} warnings.")
    return 1 if report.errors or (args.fail_on_warning and report.warnings) else 0


if __name__ == "__main__":
    sys.exit(main())
