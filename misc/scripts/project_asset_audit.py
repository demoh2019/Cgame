#!/usr/bin/env python3
"""Audit path portability and static res:// references in a Godot project.

Uses only Python's standard library; does not import the Godot editor or mutate
project files. Suitable for CI before an expensive asset import/build.
"""

from __future__ import annotations

import argparse
from dataclasses import asdict, dataclass
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

    def to_dict(self) -> dict:
        return {
            "summary": {
                "files_scanned": self.files_scanned,
                "references_checked": self.references_checked,
                "errors": sum(item.severity == "error" for item in self.findings),
                "warnings": sum(item.severity == "warning" for item in self.findings),
            },
            "findings": [asdict(item) for item in self.findings],
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
    for base, dirs, files in os.walk(root, topdown=True, followlinks=False):
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


def scan_project(root: Path, max_text_bytes: int = 8 * 1024 * 1024,
                 exclude: tuple[str, ...] = ()) -> Report:
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
                path.resolve().relative_to(root)
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
            if candidate.exists():
                if candidate.is_dir():
                    findings.append(Finding("error", "RESOURCE_IS_DIRECTORY", rel, lineno,
                                            "Resource reference points to a directory, not a file.", original))
                continue
            possible = index.get(portability_key(PurePosixPath(target).as_posix()), [])
            if len(possible) == 1:
                findings.append(Finding("error", "CASE_MISMATCH", rel, lineno,
                                        f"Resource path case does not match existing file: {possible[0]}", original))
            else:
                findings.append(Finding("error", "MISSING_RESOURCE", rel, lineno,
                                        "Resource path does not exist in the project.", original))

    findings.sort(key=Finding.sort_key)
    return Report(files_scanned, references_checked, findings)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", nargs="?", default=".", type=Path, help="Godot project directory (default: current directory)")
    parser.add_argument("--format", choices=("text", "json"), default="text", help="Output format")
    parser.add_argument("--exclude", action="append", default=[], metavar="GLOB",
                        help="Exclude matching relative project paths (repeatable)")
    parser.add_argument("--max-text-bytes", type=int, default=8 * 1024 * 1024,
                        help="Maximum bytes to read from a text resource")
    parser.add_argument("--fail-on-warning", action="store_true", help="Return nonzero on warnings, too")
    args = parser.parse_args(argv)
    try:
        report = scan_project(args.root, args.max_text_bytes, tuple(args.exclude))
    except ValueError as exc:
        print(f"Asset audit: {exc}", file=sys.stderr)
        return 2

    if args.format == "json":
        print(json.dumps(report.to_dict(), indent=2, ensure_ascii=False, sort_keys=True))
    else:
        for finding in report.findings:
            location = f"{finding.source}:{finding.line}" if finding.line else finding.source
            print(f"{location}: {finding.severity}: {finding.code}: {finding.message}")
        print(f"Scanned {report.files_scanned} text files, checked {report.references_checked} references: "
              f"{report.errors} errors, {report.warnings} warnings.")
    return 1 if report.errors or (args.fail_on_warning and report.warnings) else 0


if __name__ == "__main__":
    sys.exit(main())
