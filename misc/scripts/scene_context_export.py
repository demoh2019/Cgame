#!/usr/bin/env python3
"""Export a bounded, read-only Godot scene hierarchy for AI project context.

No project scripts are imported or executed. Only text scene headers are read;
property values and source code are deliberately excluded from the output.
"""

from __future__ import annotations

import argparse
from collections import deque
import json
from pathlib import Path
import posixpath
import re
import sys

HEADER = re.compile(r"^\[(?P<kind>gd_scene|node|ext_resource)\b(?P<body>.*)\]\s*$")
ATTRIBUTE = re.compile(r'\b([a-zA-Z_][\w]*)\s*=\s*(?:"((?:\\.|[^"\\])*)"|([^\s]+))')
INSTANCE = re.compile(r'\binstance\s*=\s*ExtResource\(\s*"([^"\\]+)"\s*\)')


class SceneContextError(ValueError):
    """Unsafe path, malformed scene, or exceeded resource budget."""


def attributes(header: str) -> dict[str, str]:
    """Parse the simple quoted header attributes without evaluating Godot data."""
    result = {}
    for match in ATTRIBUTE.finditer(header):
        if match.group(2) is None:
            result[match.group(1)] = match.group(3)
        else:
            try:
                result[match.group(1)] = json.loads('"' + match.group(2) + '"')
            except json.JSONDecodeError as exc:
                raise SceneContextError("Invalid escape sequence in scene header") from exc
    return result


def _resolve_resource_uri(scene_uri: str, reference: str) -> str | None:
    """Resolve res:// and project-relative paths; do not follow UID references."""
    if reference.startswith("uid://"):
        return None
    if any(c in reference for c in ("\\", "\x00", "\n", "\r")):
        raise SceneContextError("Unsafe resource reference")
    if reference.startswith("res://"):
        relative = reference[6:]
    elif reference.startswith("/") or "://" in reference or ":" in reference:
        raise SceneContextError("Unsupported resource scheme")
    else:
        relative = posixpath.join(posixpath.dirname(scene_uri[6:]), reference)
    relative = posixpath.normpath(relative)
    if relative in ("", ".", "..") or relative.startswith("../") or relative.startswith("/"):
        raise SceneContextError("Resource reference escapes the project")
    return "res://" + relative


def safe_path(root: Path, uri: str) -> Path:
    """Never follow symlinks, even those targeting paths inside the project."""
    if not uri.startswith("res://"):
        raise SceneContextError("Expected a res:// project path")
    relative = uri[6:]
    if (not relative or any(c in relative for c in ("\\", "\x00", "\n", "\r", ":"))
            or any(part in ("", ".", "..") for part in relative.split("/"))):
        raise SceneContextError("Unsafe res:// path")
    current = root
    for part in relative.split("/"):
        current = current / part
        if current.is_symlink():
            raise SceneContextError("Symlinked project resources are not inspected")
    return current


def parse_scene(text: str, uri: str) -> dict:
    """Extract node headers and explicit external dependencies, not properties."""
    seen_header = False
    nodes: list[dict] = []
    resources: list[dict] = []
    by_id: dict[str, str] = {}
    for line in text.splitlines():
        if not seen_header and not line.strip():
            continue
        match = HEADER.fullmatch(line.strip())
        if not seen_header:
            if not match or match.group("kind") != "gd_scene":
                raise SceneContextError("Not a Godot text scene")
            seen_header = True
        if not match:
            continue
        kind = match.group("kind")
        data = attributes(match.group("body"))
        if kind == "ext_resource":
            raw = data.get("path", "")
            if not raw:
                continue
            try:
                resolved = _resolve_resource_uri(uri, raw)
            except SceneContextError:
                resolved = None
            entry = {"path": resolved, "type": data.get("type", ""),
                     "status": "indexed" if resolved else "unresolved"}
            resources.append(entry)
            if resolved and "id" in data:
                by_id[data["id"]] = resolved
        elif kind == "node":
            item = {"name": data.get("name", ""),
                    "type": data.get("type", ""), "parent": data.get("parent", "")}
            instance_match = INSTANCE.search(match.group("body"))
            if instance_match:
                item["instance_scene"] = by_id.get(instance_match.group(1), "")
            nodes.append(item)
    if not seen_header:
        raise SceneContextError("Empty scene")
    return {"path": uri, "nodes": nodes,
            "resources": sorted(resources, key=lambda x: (x["path"] or "", x["type"]))}


def export_context(root: Path, scene_uri: str, *, max_depth: int = 2,
                   max_scenes: int = 32, max_nodes: int = 1000,
                   max_scene_bytes: int = 1024 * 1024) -> dict:
    """Return deterministic, bounded context for explicit opt-in AI prompts.

    The root scene is mandatory; unavailable nested scenes are warnings.
    """
    root = Path(root).resolve()
    if not root.is_dir():
        raise SceneContextError("Project root does not exist")
    if not (root / "project.godot").is_file():
        raise SceneContextError("Expected project.godot in project root")
    if max_depth < 0 or min(max_scenes, max_nodes, max_scene_bytes) < 1:
        raise SceneContextError("Invalid scene context limits")
    if not scene_uri.endswith(".tscn"):
        raise SceneContextError("Only .tscn text scenes are supported")
    safe_path(root, scene_uri)

    # Constant-time deque pops and one-time enqueue prevent quadratic
    # traversal on projects with many shared/cyclic scene dependencies.
    queue = deque([(scene_uri, 0)])
    scheduled = {scene_uri}
    scenes: list[dict] = []
    warnings: list[dict] = []
    node_count = 0
    while queue:
        uri, depth = queue.popleft()
        if len(scenes) >= max_scenes:
            raise SceneContextError("Scene count exceeds limit")
        try:
            path = safe_path(root, uri)
            if not path.is_file():
                raise SceneContextError("Scene file not found")
            if path.stat().st_size > max_scene_bytes:
                raise SceneContextError("Scene exceeds byte limit")
            parsed = parse_scene(path.read_text(encoding="utf-8"), uri)
        except (OSError, UnicodeError, SceneContextError) as exc:
            if uri == scene_uri:
                raise SceneContextError("Cannot inspect root scene: " + str(exc)) from exc
            warnings.append({"scene": uri, "reason": str(exc)})
            continue
        node_count += len(parsed["nodes"])
        if node_count > max_nodes:
            raise SceneContextError("Total node count exceeds limit")
        scenes.append(parsed)
        if depth < max_depth:
            for resource in parsed["resources"]:
                ref = resource["path"]
                if ref and ref.endswith(".tscn") and ref not in scheduled:
                    scheduled.add(ref)
                    queue.append((ref, depth + 1))

    scenes.sort(key=lambda item: item["path"])
    return {"root_scene": scene_uri,
            "summary": {"scenes": len(scenes), "nodes": node_count,
                        "external_resources": sum(len(s["resources"]) for s in scenes)},
            "scenes": scenes, "warnings": sorted(warnings, key=lambda x: (x["scene"], x["reason"]))}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("project", type=Path, help="Godot project directory")
    parser.add_argument("--scene", required=True, help="Root text scene, e.g. res://main.tscn")
    parser.add_argument("--max-depth", type=int, default=2)
    parser.add_argument("--max-scenes", type=int, default=32)
    parser.add_argument("--max-nodes", type=int, default=1000)
    parser.add_argument("--max-scene-bytes", type=int, default=1024 * 1024)
    args = parser.parse_args(argv)
    try:
        data = export_context(args.project, args.scene, max_depth=args.max_depth,
                              max_scenes=args.max_scenes, max_nodes=args.max_nodes,
                              max_scene_bytes=args.max_scene_bytes)
    except SceneContextError as exc:
        print("Scene context: " + str(exc), file=sys.stderr)
        return 2
    print(json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
