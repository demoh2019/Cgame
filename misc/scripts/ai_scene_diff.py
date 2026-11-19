#!/usr/bin/env python3
"""Read-only structural preview of Godot scene changes for AI Game Builder.

Compare the same scene across original/staged Godot projects. Never executes
scripts, modifies project files, or includes node properties/script bodies.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

from scene_context_export import SceneContextError, export_context, safe_path

SCHEMA = "cgame.ai_scene_diff.v1"


class SceneDiffError(ValueError):
    """Unsafe project, ambiguous scene identity or exceeded preview budget."""


def _project_root(project: Path) -> Path:
    root = Path(project).absolute()
    manifest = root / "project.godot"
    if (root.is_symlink() or not root.is_dir() or not manifest.is_file()
            or manifest.is_symlink()):
        raise SceneDiffError("Expected a real Godot project with regular project.godot")
    return root


def _node_map(scene: dict) -> dict[tuple[str, str], dict]:
    result = {}
    for node in scene["nodes"]:
        # The parent path and node name are stable structural identities within
        # a .tscn file. A rename/move is represented as remove + add.
        identity = (node["parent"], node["name"])
        if identity in result:
            raise SceneDiffError("Ambiguous duplicate scene node identity")
        result[identity] = {key: node[key] for key in
                            ("name", "parent", "type", "instance_scene") if key in node}
    return result


def _resource_map(scene: dict) -> dict[tuple[str, str, str], dict]:
    result = {}
    for resource in scene["resources"]:
        # Identical external-resource declarations are collapsed. Resource IDs
        # are intentionally omitted by the metadata-only context exporter.
        identity = (resource["path"] or "", resource["type"], resource["status"])
        result[identity] = {"path": resource["path"], "type": resource["type"],
                            "status": resource["status"]}
    return result


def _file_bytes(root: Path, uri: str, max_bytes: int) -> bytes:
    # A second bounded read is used only to detect property-only modifications;
    # the content itself is never added to the diff or printed.
    path = safe_path(root, uri)
    if not path.is_file() or path.stat().st_size > max_bytes:
        raise SceneDiffError("Scene changed or exceeded byte limit during preview")
    with path.open("rb") as handle:
        data = handle.read(max_bytes + 1)
    if len(data) > max_bytes:
        raise SceneDiffError("Scene changed or exceeded byte limit during preview")
    return data


def compare_projects(before_project: Path, after_project: Path, scene_uri: str,
                     *, max_depth: int = 2, max_scenes: int = 32,
                     max_nodes: int = 1000, max_scene_bytes: int = 1024 * 1024,
                     max_changes: int = 200, max_output_bytes: int = 128 * 1024) -> dict:
    """Return sorted, bounded metadata changes; never run or write project code.

    Inputs are separate Godot projects, typically an untouched original and an
    explicitly staged candidate. Text-only changes are indicated but not shown.
    """
    if not 0 <= max_changes <= 10000 or not 1024 <= max_output_bytes <= 4 * 1024 * 1024:
        raise SceneDiffError("Invalid preview change/output limits")
    before_root = _project_root(before_project)
    after_root = _project_root(after_project)
    left = export_context(before_root, scene_uri, max_depth=max_depth,
                          max_scenes=max_scenes, max_nodes=max_nodes,
                          max_scene_bytes=max_scene_bytes)
    right = export_context(after_root, scene_uri, max_depth=max_depth,
                           max_scenes=max_scenes, max_nodes=max_nodes,
                           max_scene_bytes=max_scene_bytes)
    old_scenes = {scene["path"]: scene for scene in left["scenes"]}
    new_scenes = {scene["path"]: scene for scene in right["scenes"]}
    changes = []
    counts = {"added_scenes": 0, "removed_scenes": 0,
              "added_nodes": 0, "removed_nodes": 0, "modified_nodes": 0,
              "added_resources": 0, "removed_resources": 0}

    def add(kind: str, action: str, scene: str, before=None, after=None) -> None:
        record = {"kind": kind, "action": action, "scene": scene}
        if before is not None:
            record["before"] = before
        if after is not None:
            record["after"] = after
        changes.append(record)
        plural = {"scene": "scenes", "node": "nodes", "resource": "resources"}[kind]
        key = {"added": "added", "removed": "removed", "modified": "modified"}[action] + "_" + plural
        counts[key] += 1

    for scene_uri_current in sorted(set(old_scenes) | set(new_scenes)):
        old = old_scenes.get(scene_uri_current)
        new = new_scenes.get(scene_uri_current)
        if old is None:
            add("scene", "added", scene_uri_current)
        elif new is None:
            add("scene", "removed", scene_uri_current)
        old_nodes = _node_map(old) if old else {}
        new_nodes = _node_map(new) if new else {}
        for key in sorted(set(old_nodes) | set(new_nodes)):
            prev, next_ = old_nodes.get(key), new_nodes.get(key)
            if prev is None:
                add("node", "added", scene_uri_current, after=next_)
            elif next_ is None:
                add("node", "removed", scene_uri_current, before=prev)
            elif prev != next_:
                add("node", "modified", scene_uri_current, before=prev, after=next_)
        old_resources = _resource_map(old) if old else {}
        new_resources = _resource_map(new) if new else {}
        for key in sorted(set(old_resources) | set(new_resources)):
            prev, next_ = old_resources.get(key), new_resources.get(key)
            if prev is None:
                add("resource", "added", scene_uri_current, after=next_)
            elif next_ is None:
                add("resource", "removed", scene_uri_current, before=prev)

    # A scene can change property values while keeping exactly the same node and
    # resource declarations. Report that fact without disclosing values/hashes.
    text_changed_scenes = []
    for uri in sorted(set(old_scenes) & set(new_scenes)):
        if _file_bytes(before_root, uri, max_scene_bytes) != _file_bytes(after_root, uri, max_scene_bytes):
            text_changed_scenes.append(uri)
    summary = {"scenes_before": len(old_scenes), "scenes_after": len(new_scenes),
               "nodes_before": left["summary"]["nodes"],
               "nodes_after": right["summary"]["nodes"],
               "text_changed_scenes": len(text_changed_scenes),
               "total_changes": len(changes), **counts}
    summary["changes_reported"] = min(len(changes), max_changes)
    result = {"schema": SCHEMA, "root_scene": scene_uri,
              "summary": summary, "text_changed_scenes": text_changed_scenes,
              "warnings": {"before": left["warnings"], "after": right["warnings"]},
              "changes": changes[:max_changes], "truncated": len(changes) > max_changes}

    def size() -> int:
        return len(json.dumps(result, ensure_ascii=False, sort_keys=True,
                              separators=(",", ":")).encode("utf-8"))

    if size() > max_output_bytes:
        # The serialized byte length grows monotonically with the number of
        # displayed changes. Binary search avoids serializing the whole list
        # once for every removed change on large AI-generated scene diffs.
        available_changes = result["changes"]
        result["truncated"] = True
        low, high = 0, len(available_changes) - 1
        best = -1
        while low <= high:
            mid = (low + high) // 2
            result["changes"] = available_changes[:mid]
            summary["changes_reported"] = mid
            if size() <= max_output_bytes:
                best = mid
                low = mid + 1
            else:
                high = mid - 1
        if best < 0:
            raise SceneDiffError("Scene diff metadata exceeds output byte limit")
        result["changes"] = available_changes[:best]
        summary["changes_reported"] = best
    return result


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("before_project", type=Path, help="Unmodified Godot project directory")
    parser.add_argument("after_project", type=Path, help="Staged Godot project directory")
    parser.add_argument("--scene", required=True, help="Text scene URI, e.g. res://main.tscn")
    parser.add_argument("--max-depth", type=int, default=2)
    parser.add_argument("--max-scenes", type=int, default=32)
    parser.add_argument("--max-nodes", type=int, default=1000)
    parser.add_argument("--max-scene-bytes", type=int, default=1024 * 1024)
    parser.add_argument("--max-changes", type=int, default=200)
    parser.add_argument("--max-output-bytes", type=int, default=128 * 1024)
    opts = parser.parse_args(argv)
    try:
        report = compare_projects(opts.before_project, opts.after_project,
                                  opts.scene, max_depth=opts.max_depth,
                                  max_scenes=opts.max_scenes, max_nodes=opts.max_nodes,
                                  max_scene_bytes=opts.max_scene_bytes,
                                  max_changes=opts.max_changes,
                                  max_output_bytes=opts.max_output_bytes)
    except (OSError, UnicodeError, SceneContextError, SceneDiffError) as exc:
        print("AI scene diff: " + str(exc), file=sys.stderr)
        return 2
    # Compact output preserves the documented max_output_bytes bound on stdout.
    sys.stdout.write(json.dumps(report, ensure_ascii=False, sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
