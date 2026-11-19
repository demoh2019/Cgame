#!/usr/bin/env python3
"""Deterministic content manifests for Godot project distribution (format v1).

This tool does not download or install content; it prepares and validates the
integrity inventory consumed by a future versioned delivery client.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import sys
import tempfile
import unicodedata

FORMAT_VERSION = 1
MAX_MANIFEST_BYTES = 16 * 1024 * 1024
MAX_FILES = 100_000
SKIP_DIRS = {".git", ".godot", ".hg", ".svn", "__pycache__"}
SKIP_FILES = {".DS_Store", "Thumbs.db"}
WINDOWS_RESERVED = {"CON", "PRN", "AUX", "NUL"} | {f"COM{i}" for i in range(1, 10)} | {f"LPT{i}" for i in range(1, 10)}
SHA256_RE = re.compile(r"[0-9a-f]{64}\Z")


class ManifestError(Exception):
    """Invalid input, unsafe filesystem entry, or changed file during hashing."""


def validate_path(value):
    """Reject non-portable, ambiguous and traversal paths without normalizing them."""
    if not isinstance(value, str) or not value or len(value) > 4096:
        raise ManifestError("File path must be a non-empty UTF-8 string (max 4096 characters)")
    if value != unicodedata.normalize("NFC", value):
        raise ManifestError(f"Non-NFC file path: {value!r}")
    if "\\" in value or ":" in value or value.startswith("/"):
        raise ManifestError(f"Non-portable file path: {value!r}")
    for component in value.split("/"):
        if (not component or component in {".", ".."} or component.endswith((" ", "."))
                or any(c in '<>"|?*' or ord(c) < 32 or ord(c) == 127 or 0xD800 <= ord(c) <= 0xDFFF for c in component)
                or component.split(".", 1)[0].upper() in WINDOWS_RESERVED):
            raise ManifestError(f"Unsafe file path: {value!r}")
    return value


def _check_aliases(paths):
    seen = {}
    files = set()
    for path in paths:
        validate_path(path)
        parts = path.split("/")
        for i in range(1, len(parts) + 1):
            prefix = "/".join(parts[:i])
            folded = prefix.casefold()
            previous = seen.setdefault(folded, prefix)
            if previous != prefix:
                raise ManifestError(f"Case-insensitive path collision: {previous!r} and {prefix!r}")
        files.add(path.casefold())

    # A manifest must never describe both a file and a directory at one path.
    # Such a manifest cannot be installed safely on any filesystem.
    for path in paths:
        parts = path.split("/")
        for i in range(1, len(parts)):
            parent = "/".join(parts[:i])
            if parent.casefold() in files:
                raise ManifestError(f"File/directory path collision: {parent!r} and {path!r}")


def _project_files(root, excluded_manifest=None):
    if root.is_symlink() or not root.is_dir():
        raise ManifestError(f"Project root must be a real directory: {root}")
    def reject_walk_error(error):
        # os.walk ignores unreadable directories unless onerror is provided.
        raise ManifestError(f"Cannot traverse project tree: {error}")

    found = []
    for current, dirs, files in os.walk(root, followlinks=False, onerror=reject_walk_error):
        location = Path(current)
        for directory in list(dirs):
            if directory in SKIP_DIRS:
                dirs.remove(directory)
                continue
            entry = location / directory
            if entry.is_symlink():
                raise ManifestError(f"Symlink directory is not distributable: {entry}")
        dirs.sort()
        for name in sorted(files):
            if name in SKIP_FILES:
                continue
            entry = location / name
            relative = entry.relative_to(root).as_posix()
            if relative == excluded_manifest:
                continue
            validate_path(relative)
            if entry.is_symlink():
                raise ManifestError(f"Symlink file is not distributable: {relative}")
            if not entry.is_file():
                raise ManifestError(f"Non-regular file is not distributable: {relative}")
            found.append(relative)
            if len(found) > MAX_FILES:
                raise ManifestError(f"Too many files (max {MAX_FILES})")
    _check_aliases(found)
    return sorted(found)


def _digest_file(path):
    """Hash using a file descriptor, rejecting symlinks and concurrent changes."""
    flags = os.O_RDONLY | getattr(os, "O_BINARY", 0) | getattr(os, "O_NOFOLLOW", 0)
    fd = os.open(path, flags)
    try:
        before = os.fstat(fd)
        if not stat.S_ISREG(before.st_mode):
            raise ManifestError(f"Not a regular file: {path}")
        digest = hashlib.sha256()
        with os.fdopen(os.dup(fd), "rb") as stream:
            while True:
                block = stream.read(1024 * 1024)
                if not block:
                    break
                digest.update(block)
        after = os.fstat(fd)
        if ((before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns) !=
                (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns)):
            raise ManifestError(f"File changed while hashing: {path}")
        return {"bytes": before.st_size, "sha256": digest.hexdigest()}
    finally:
        os.close(fd)


def inventory(root, excluded_manifest=None):
    files = _project_files(root, excluded_manifest)
    entries = []
    for relative in files:
        # A symlink substituted after scanning must not be followed.
        full_path = root / relative
        if full_path.is_symlink():
            raise ManifestError(f"File became a symlink during scan: {relative}")
        entries.append({"path": relative, **_digest_file(full_path)})
    return {"format": FORMAT_VERSION, "files": entries}


def load_manifest(path):
    if path.stat().st_size > MAX_MANIFEST_BYTES:
        raise ManifestError("Manifest exceeds the 16 MiB limit")
    with path.open("r", encoding="utf-8") as stream:
        doc = json.load(stream)
    if not isinstance(doc, dict) or set(doc) != {"format", "files"} or type(doc["format"]) is not int or doc["format"] != FORMAT_VERSION:
        raise ManifestError("Unsupported or malformed content manifest")
    entries = doc["files"]
    if not isinstance(entries, list) or len(entries) > MAX_FILES:
        raise ManifestError("Invalid manifest file list")
    names = []
    for entry in entries:
        if not isinstance(entry, dict) or set(entry) != {"path", "bytes", "sha256"}:
            raise ManifestError("Invalid manifest entry structure")
        names.append(validate_path(entry["path"]))
        if type(entry["bytes"]) is not int or entry["bytes"] < 0:
            raise ManifestError("Invalid manifest file size")
        if not isinstance(entry["sha256"], str) or not SHA256_RE.fullmatch(entry["sha256"]):
            raise ManifestError("Invalid manifest SHA-256")
    if names != sorted(set(names)):
        raise ManifestError("Manifest paths must be sorted and unique")
    _check_aliases(names)
    return doc


def _excluded_relative(root, manifest_path):
    try:
        return manifest_path.absolute().relative_to(root.absolute()).as_posix()
    except ValueError:
        return None


def verify(root, manifest_path):
    expected = load_manifest(manifest_path)
    actual = inventory(root, _excluded_relative(root, manifest_path))
    old = {item["path"]: item for item in expected["files"]}
    new = {item["path"]: item for item in actual["files"]}
    missing = sorted(old.keys() - new.keys())
    extra = sorted(new.keys() - old.keys())
    modified = sorted(name for name in old.keys() & new.keys() if old[name] != new[name])
    return {"ok": not (missing or extra or modified), "missing": missing, "extra": extra, "modified": modified}


def diff(old, new):
    before = {item["path"]: item for item in old["files"]}
    after = {item["path"]: item for item in new["files"]}
    added = sorted(after.keys() - before.keys())
    removed = sorted(before.keys() - after.keys())
    modified = sorted(name for name in before.keys() & after.keys() if before[name] != after[name])
    retained = len(before.keys() & after.keys()) - len(modified)
    return {"added": added, "removed": removed, "modified": modified,
            "unchanged": retained,
            "download_bytes": sum(after[name]["bytes"] for name in added + modified)}


def _write_manifest(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temp_path = tempfile.mkstemp(prefix=".content-manifest-", suffix=".tmp", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as stream:
            json.dump(data, stream, ensure_ascii=False, sort_keys=True, indent=2)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temp_path, path)
    finally:
        if os.path.exists(temp_path):
            os.unlink(temp_path)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    build = commands.add_parser("build", help="Generate stable SHA-256 inventory for a project")
    build.add_argument("root", type=Path)
    build.add_argument("--output", "-o", type=Path, required=True)
    check = commands.add_parser("verify", help="Check a project against a manifest")
    check.add_argument("root", type=Path)
    check.add_argument("manifest", type=Path)
    delta = commands.add_parser("diff", help="Compute changed content for a version upgrade")
    delta.add_argument("old", type=Path)
    delta.add_argument("new", type=Path)
    arguments = parser.parse_args(argv)
    try:
        if arguments.command == "build":
            doc = inventory(arguments.root, _excluded_relative(arguments.root, arguments.output))
            _write_manifest(arguments.output, doc)
            print(json.dumps({"files": len(doc["files"]), "manifest": str(arguments.output)}, sort_keys=True))
            return 0
        if arguments.command == "verify":
            report = verify(arguments.root, arguments.manifest)
            print(json.dumps(report, ensure_ascii=False, sort_keys=True))
            return 0 if report["ok"] else 1
        report = diff(load_manifest(arguments.old), load_manifest(arguments.new))
        print(json.dumps(report, ensure_ascii=False, sort_keys=True))
        return 0
    except (ManifestError, OSError, UnicodeError, ValueError, json.JSONDecodeError) as error:
        print(f"content_manifest: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())