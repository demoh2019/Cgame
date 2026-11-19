#!/usr/bin/env python3
"""Trace direct and reverse static res:// dependencies of Godot project assets.

This command is an offline, read-only companion to project_asset_audit.py.
It reuses the audit scanner's supported file types, ignores, and literal parser.
"""

from __future__ import annotations

import argparse
from collections import defaultdict, deque
from dataclasses import dataclass
import json
from pathlib import Path
import sys

from project_asset_audit import TEXT_EXTENSIONS, _iter_static_references, _iterate_entries


@dataclass(frozen=True, order=True)
class Reference:
    source: str
    target: str
    line: int

    def to_dict(self) -> dict:
        return {"source": "res://" + self.source,
                "target": "res://" + self.target, "line": self.line}


@dataclass(frozen=True)
class ReferenceGraph:
    nodes: tuple[str, ...]
    references: tuple[Reference, ...]


def build_graph(root: Path, max_text_bytes: int = 8 * 1024 * 1024,
                exclude: tuple[str, ...] = ()) -> ReferenceGraph:
    """Index valid, statically quoted res:// references to existing project files.

    References to missing, differently-cased, excluded, or symlinked files are
    deliberately omitted. Use project_asset_audit.py for diagnostics on them.
    """
    root = Path(root).resolve()
    if not root.is_dir():
        raise ValueError(f"Project root is not a directory: {root}")
    if max_text_bytes < 1:
        raise ValueError("max_text_bytes must be at least 1")

    # Do not follow file or directory symlinks, including internal symlinks:
    # referencing an alias should not silently invent a graph edge.
    files = {
        relative: path for path, relative in _iterate_entries(root, exclude)
        if not path.is_symlink() and path.is_file()
    }
    references = []
    for relative in sorted(files):
        path = files[relative]
        if path.suffix.lower() not in TEXT_EXTENSIONS:
            continue
        try:
            if path.stat().st_size > max_text_bytes:
                continue
            content = path.read_text(encoding="utf-8")
        except (OSError, UnicodeError):
            continue
        for line, target in _iter_static_references(content, path.suffix.lower()):
            # Membership matches literal casing and separators. This also
            # prevents parent traversal and generated cache references.
            if target in files:
                references.append(Reference(relative, target, line))

    return ReferenceGraph(tuple(sorted(files)), tuple(sorted(references)))


def trace_references(graph: ReferenceGraph, asset: str, direction: str = "both",
                     depth: int = 1) -> ReferenceGraph:
    """Return the induced subgraph reachable from asset in selected directions.

    Depth 0 includes only the selected asset; -1 means unlimited traversal.
    Arrows always go from referring resource to the referenced resource.
    """
    if asset.startswith("res://"):
        asset = asset[6:]
    if asset not in graph.nodes:
        raise ValueError(f"Asset not found among scanned files: res://{asset}")
    if direction not in {"dependencies", "referencers", "both"}:
        raise ValueError("direction must be dependencies, referencers or both")
    if depth < -1:
        raise ValueError("depth must be -1 (unlimited) or nonnegative")

    outgoing: dict[str, set[str]] = defaultdict(set)
    incoming: dict[str, set[str]] = defaultdict(set)
    for reference in graph.references:
        outgoing[reference.source].add(reference.target)
        incoming[reference.target].add(reference.source)

    visited = {asset}
    queue = deque([(asset, 0)])
    while queue:
        current, level = queue.popleft()
        if depth != -1 and level >= depth:
            continue
        neighbors = set()
        if direction in {"dependencies", "both"}:
            neighbors.update(outgoing[current])
        if direction in {"referencers", "both"}:
            neighbors.update(incoming[current])
        for neighbor in sorted(neighbors):
            if neighbor not in visited:
                visited.add(neighbor)
                queue.append((neighbor, level + 1))

    return ReferenceGraph(
        tuple(sorted(visited)),
        tuple(reference for reference in graph.references
              if reference.source in visited and reference.target in visited),
    )


def to_json(graph: ReferenceGraph, asset: str, direction: str, depth: int) -> str:
    return json.dumps({
        "asset": asset if asset.startswith("res://") else "res://" + asset,
        "depth": depth,
        "direction": direction,
        "summary": {"assets": len(graph.nodes), "references": len(graph.references)},
        "nodes": ["res://" + path for path in graph.nodes],
        "references": [item.to_dict() for item in graph.references],
    }, ensure_ascii=False, sort_keys=True, indent=2)


def to_dot(graph: ReferenceGraph) -> str:
    """Produce deterministic Graphviz DOT without interpolating raw filenames."""
    def quote(path: str) -> str:
        # JSON double-quoted strings safely escape DOT quotes and backslashes.
        return json.dumps("res://" + path, ensure_ascii=False)

    lines = ["digraph AssetReferences {", "  rankdir=LR;"]
    for node in graph.nodes:
        lines.append(f"  {quote(node)};")
    for source, target in sorted({(ref.source, ref.target) for ref in graph.references}):
        lines.append(f"  {quote(source)} -> {quote(target)};")
    lines.append("}")
    return "\n".join(lines) + "\n"


def to_text(graph: ReferenceGraph, asset: str) -> str:
    selected = asset if asset.startswith("res://") else "res://" + asset
    lines = [f"Asset: {selected}"]
    for reference in graph.references:
        lines.append(f"res://{reference.source}:{reference.line} -> res://{reference.target}")
    if not graph.references:
        lines.append("No static references in the selected graph.")
    lines.append(f"{len(graph.nodes)} assets, {len(graph.references)} references.")
    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", nargs="?", type=Path, default=Path("."),
                        help="Godot project root (default: current directory)")
    parser.add_argument("--asset", required=True, metavar="RES_PATH",
                        help="Select a project file, e.g. res://scenes/player.tscn")
    parser.add_argument("--direction", choices=("dependencies", "referencers", "both"),
                        default="both", help="Traversal direction (default: both)")
    parser.add_argument("--depth", type=int, default=1,
                        help="Maximum reference hops; -1 for unlimited (default: 1)")
    parser.add_argument("--format", choices=("text", "json", "dot"), default="text",
                        help="Output format (default: text)")
    parser.add_argument("--exclude", action="append", default=[], metavar="GLOB",
                        help="Exclude paths/globs from the project index (repeatable)")
    parser.add_argument("--max-text-bytes", type=int, default=8 * 1024 * 1024,
                        help="Largest text resource to inspect")
    args = parser.parse_args(argv)

    try:
        graph = build_graph(args.root, args.max_text_bytes, tuple(args.exclude))
        selected = trace_references(graph, args.asset, args.direction, args.depth)
    except ValueError as exc:
        print(f"Asset reference graph: {exc}", file=sys.stderr)
        return 2

    if args.format == "json":
        print(to_json(selected, args.asset, args.direction, args.depth))
    elif args.format == "dot":
        print(to_dot(selected), end="")
    else:
        print(to_text(selected, args.asset), end="")
    return 0


if __name__ == "__main__":
    sys.exit(main())
