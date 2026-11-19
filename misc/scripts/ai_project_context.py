#!/usr/bin/env python3
"""Export a bounded, read-only Godot project outline for an opt-in AI assistant."""

import argparse
import json
from itertools import islice
import os
from pathlib import Path
import re
import sys

SCHEMA = "cgame.ai_project_context.v1"
KINDS = {".tscn": "scene", ".tres": "resource", ".gd": "script", ".gdshader": "shader"}
SKIP_DIRS = {".git", ".godot", ".hg", ".svn", "__pycache__"}
NODE = re.compile(r"^\[node\b([^\]\n]*)\]", re.MULTILINE)
RESOURCE = re.compile(r"^\[ext_resource\b([^\]\n]*)\]", re.MULTILINE)
ATTRIBUTE = re.compile(r'(\w+)="([^"\n]{0,256})"')
FUNCTION = re.compile(r"^\s*(?:static\s+)?func\s+([a-zA-Z_]\w*)\s*\(", re.MULTILINE)
IDENTIFIER = re.compile(r"^[A-Za-z_]\w*$")


class ContextError(ValueError):
    """An invalid project or unsafe scan request."""


def _attributes(fragment):
    return dict(ATTRIBUTE.findall(fragment))


def _outline(relative, content):
    kind = KINDS[Path(relative).suffix.lower()]
    item = {"path": relative, "kind": kind}
    if kind == "scene":
        # Avoid materializing every node in a large generated scene when the
        # context format includes at most the first 64 nodes.
        item["nodes"] = [
            {key: attrs[key] for key in ("name", "type", "parent") if key in attrs}
            for attrs in (_attributes(match.group(1)) for match in islice(NODE.finditer(content), 64))
        ]
    elif kind == "resource":
        item["resource_types"] = sorted(set(re.findall(r'^\[sub_resource\s+type="([A-Za-z0-9_]{1,64})"', content, re.MULTILINE)))[:32]
    elif kind == "script":
        # Preserve first-occurrence order, but stop after 64 distinct names
        # instead of allocating a full match list for very large scripts.
        functions = []
        seen_functions = set()
        for match in FUNCTION.finditer(content):
            name = match.group(1)
            if name not in seen_functions:
                seen_functions.add(name)
                functions.append(name)
                if len(functions) == 64:
                    break
        item["functions"] = functions
        for field, pattern in (
            ("class_name", r"^\s*class_name\s+([A-Za-z_]\w*)\b"),
            ("extends", r"^\s*extends\s+([A-Za-z_]\w*)\b"),
        ):
            found = re.search(pattern, content, re.MULTILINE)
            if found and IDENTIFIER.fullmatch(found.group(1)):
                item[field] = found.group(1)
    if kind in ("scene", "resource"):
        refs = []
        for match in RESOURCE.finditer(content):
            attrs = _attributes(match.group(1))
            path = attrs.get("path", "")
            if path.startswith("res://") and len(path) <= 256 and ".." not in path.split("/"):
                refs.append(path)
        item["references"] = sorted(set(refs))[:64]
    return item


def _read_text(path, max_file_bytes):
    # No generated file content is ever exported: only structural metadata.
    flags = os.O_RDONLY | getattr(os, "O_BINARY", 0) | getattr(os, "O_NOFOLLOW", 0)
    descriptor = os.open(str(path), flags)
    with os.fdopen(descriptor, "rb") as handle:
        raw = handle.read(max_file_bytes + 1)
    if len(raw) > max_file_bytes or b"\x00" in raw:
        return None
    try:
        return raw.decode("utf-8-sig")
    except UnicodeError:
        return None


def build_context(project, max_files=128, max_file_bytes=65536, max_output_bytes=65536):
    """Return deterministic metadata, never following symlinks or running game code."""
    if not 1 <= max_files <= 10000 or not 1 <= max_file_bytes <= 1048576 or not 512 <= max_output_bytes <= 1048576:
        raise ContextError("Invalid file/output limits")
    root = Path(project).absolute()
    if root.is_symlink() or not root.is_dir() or not (root / "project.godot").is_file() or (root / "project.godot").is_symlink():
        raise ContextError("Expected a real Godot project directory with project.godot")
    candidates = []

    def onerror(exc):
        raise ContextError("Cannot scan project: {}".format(exc))

    for current, directories, files in os.walk(root, followlinks=False, onerror=onerror):
        folder = Path(current)
        directories[:] = sorted(d for d in directories if not d.startswith(".") and d not in SKIP_DIRS and not (folder / d).is_symlink())
        for name in sorted(files):
            entry = folder / name
            if name.startswith(".") or entry.suffix.lower() not in KINDS or entry.is_symlink() or not entry.is_file():
                continue
            candidates.append((entry.relative_to(root).as_posix(), entry))
            if len(candidates) > 20000:
                raise ContextError("Too many candidate files (limit: 20000)")
    candidates.sort(key=lambda pair: (pair[0].casefold(), pair[0]))
    result = {"schema": SCHEMA, "files": [], "truncated": False, "scanned_files": len(candidates), "skipped_files": 0}
    # Account for encoded list entries incrementally. Re-encoding the whole
    # accepted list at each step otherwise causes O(files^2) JSON work.
    accepted_payload_bytes = 0
    for relative, path in candidates:
        if len(result["files"]) >= max_files:
            result["skipped_files"] += 1
            result["truncated"] = True
            continue
        try:
            content = _read_text(path, max_file_bytes)
        except OSError:
            content = None
        if content is None:
            result["skipped_files"] += 1
            result["truncated"] = True
            continue
        item = _outline(relative, content)
        encoded_item_bytes = len(json.dumps(item, ensure_ascii=False, separators=(",", ":")).encode("utf-8"))
        # Only reserialize constant-size metadata so the current skip count
        # and truncated flag retain the exact original JSON byte accounting.
        envelope_bytes = len(json.dumps({**result, "files": []},
                                        ensure_ascii=False, separators=(",", ":")).encode("utf-8"))
        separator_bytes = 1 if result["files"] else 0
        added_bytes = separator_bytes + encoded_item_bytes
        if envelope_bytes + accepted_payload_bytes + added_bytes > max_output_bytes:
            result["skipped_files"] += 1
            result["truncated"] = True
            continue
        result["files"].append(item)
        accepted_payload_bytes += added_bytes
    return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("project", type=Path)
    parser.add_argument("--max-files", type=int, default=128)
    parser.add_argument("--max-file-bytes", type=int, default=65536)
    parser.add_argument("--max-output-bytes", type=int, default=65536)
    opts = parser.parse_args(argv)
    try:
        context = build_context(opts.project, opts.max_files, opts.max_file_bytes, opts.max_output_bytes)
    except ContextError as exc:
        parser.error(str(exc))
    print(json.dumps(context, ensure_ascii=False, sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
