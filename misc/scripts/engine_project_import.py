#!/usr/bin/env python3
"""Conservative, offline migration of portable assets and Unity scene skeletons to Godot.

No compiled gameplay, proprietary engine binaries or native scripts are converted.
"""

from __future__ import annotations

import argparse
from collections import Counter
from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import sys
from urllib.parse import unquote, urlsplit


PORTABLE = frozenset({
    ".png", ".jpg", ".jpeg", ".webp", ".bmp", ".tga", ".svg", ".hdr", ".exr",
    ".wav", ".ogg", ".mp3", ".ttf", ".otf", ".glb", ".gltf", ".fbx",
    ".obj", ".mtl", ".dae", ".blend",
})
IGNORE_DIRS = frozenset({
    ".git", ".godot", ".idea", ".vs", "Library", "Temp", "Obj", "Logs",
    "Build", "Builds", "Binaries", "Intermediate", "Saved", "node_modules",
})
HEADER = re.compile(r"^--- !u!(\d+) &(-?\d+)(?: stripped)?\s*$", re.MULTILINE)
NUMBER = r"[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?"


class ImportErrorDetail(ValueError):
    """An unsafe or unsupported migration operation."""


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def file_digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def detect_engine(source: Path) -> str:
    if (source / "Assets").is_dir() and (source / "ProjectSettings").is_dir():
        return "unity"
    if any(p.is_file() for p in source.glob("*.uproject")):
        return "unreal"
    if any(p.is_file() for p in source.glob("*.yyp")):
        return "gamemaker"
    if (source / "game.project").is_file():
        return "defold"
    raise ImportErrorDetail("Cannot detect project; use --engine generic for an exported asset directory")


def asset_root(source: Path, engine: str) -> Path:
    choice = {"unity": "Assets", "unreal": "Content"}.get(engine)
    root = source / choice if choice else source
    if not root.is_dir():
        raise ImportErrorDetail(f"{engine} asset directory is missing: {root}")
    return root


def iter_files(root: Path):
    for directory, dirs, files in os.walk(root, topdown=True, followlinks=False):
        dirs[:] = sorted(d for d in dirs if d not in IGNORE_DIRS and not d.startswith(".")
                         and not (Path(directory) / d).is_symlink())
        for name in sorted(files):
            path = Path(directory) / name
            if name.startswith(".") or path.is_symlink() or not path.is_file():
                continue
            yield path


def gltf_dependencies(path: Path, root: Path) -> tuple[set[Path], list[str]]:
    extra, warnings = set(), []
    try:
        gltf = json.loads(path.read_text(encoding="utf-8"))
        urls = [v.get("uri") for section in ("buffers", "images")
                for v in gltf.get(section, []) if isinstance(v, dict)]
    except (ValueError, UnicodeError, OSError, AttributeError) as exc:
        return extra, [f"{path.relative_to(root)}: invalid glTF JSON ({type(exc).__name__})"]
    for uri in urls:
        if not isinstance(uri, str) or uri.startswith("data:"):
            continue
        parsed = urlsplit(uri)
        if parsed.scheme or parsed.netloc or parsed.query or parsed.fragment:
            warnings.append(f"{path.relative_to(root)}: external glTF URI not copied")
            continue
        raw_candidate = path.parent / unquote(parsed.path)
        candidate = raw_candidate.resolve()
        if (raw_candidate.is_symlink() or not candidate.is_relative_to(root.resolve())
                or not candidate.is_file() or any(p in IGNORE_DIRS for p in candidate.parts)):
            warnings.append(f"{path.relative_to(root)}: unsafe or missing glTF dependency")
            continue
        extra.add(candidate)
    return extra, warnings


def field(document: str, name: str, default: str = "") -> str:
    match = re.search(r"^\s*" + re.escape(name) + r":\s*(.*?)\s*$", document, re.MULTILINE)
    return match.group(1) if match else default


def components(document: str, key: str, defaults: tuple[float, ...]) -> tuple[float, ...]:
    raw = field(document, key)
    keys = "xyzw"[:len(defaults)]
    try:
        values = [float(re.search(r"(?:^|[,{}])\s*" + k + r":\s*(" + NUMBER + r")\b", raw).group(1))
                  for k in keys]
        if not all(abs(x) < 1e15 for x in values):
            raise ValueError("non-finite vector")
        return tuple(values)
    except (AttributeError, ValueError, OverflowError):
        return defaults


def ref(document: str, key: str) -> str:
    raw = field(document, key)
    match = re.search(r"fileID:\s*(-?\d+)", raw)
    return match.group(1) if match else "0"


def godot_name(value: str) -> str:
    """Godot NodePath cannot contain separators, colon or control characters."""
    value = re.sub(r'[/:@"%\\\x00-\x1f]', "_", value).strip()
    return value[:90] or "GameObject"


def vector(values: tuple[float, ...]) -> str:
    return "Vector3(" + ", ".join(format(x, ".9g") for x in values) + ")"


def convert_unity_scene(contents: str) -> tuple[bytes, int, list[str]]:
    """Convert only text YAML GameObjects and their local 3D Transforms to nodes."""
    sections = list(HEADER.finditer(contents))
    if not sections or not contents.lstrip().startswith(("%YAML", "--- !u!")):
        raise ImportErrorDetail("Not a Unity text-serialized scene")
    objects, transforms, unsupported = {}, {}, Counter()
    for index, match in enumerate(sections):
        type_id, file_id = match.group(1), match.group(2)
        body = contents[match.end():sections[index + 1].start() if index + 1 < len(sections) else len(contents)]
        if type_id == "1":
            objects[file_id] = (field(body, "m_Name", "GameObject"), field(body, "m_IsActive", "1") != "0")
        elif type_id == "4":
            transforms[file_id] = (ref(body, "m_GameObject"), ref(body, "m_Father"),
                                    components(body, "m_LocalPosition", (0, 0, 0)),
                                    components(body, "m_LocalRotation", (0, 0, 0, 1)),
                                    components(body, "m_LocalScale", (1, 1, 1)))
        else:
            unsupported[type_id] += 1
    by_gameobject = {item[0]: (tid, *item[1:]) for tid, item in transforms.items()
                     if item[0] in objects}
    if not by_gameobject:
        raise ImportErrorDetail("No GameObjects with 3D Transforms")
    warnings = []
    if unsupported:
        warnings.append("Unity components not converted: " + ", ".join(
            f"class {k} ({n})" for k, n in sorted(unsupported.items())))
    omitted = len(objects) - len(by_gameobject)
    if omitted:
        warnings.append(f"GameObjects without 3D Transform omitted: {omitted}")

    paths, lines, active_nodes = {}, ["[gd_scene load_steps=1 format=3]", "",
                                      '[node name="ImportedUnityScene" type="Node3D"]', ""], set()
    used_names = {}
    def emit(game_id: str, stack: frozenset[str] = frozenset()) -> str:
        if game_id in paths:
            return paths[game_id]
        if game_id in stack:
            raise ImportErrorDetail("Cyclic Unity Transform hierarchy")
        tid, father, pos, quat, scale = by_gameobject[game_id]
        parent_game = transforms.get(father, (None,))[0] if father in transforms else None
        parent = emit(parent_game, stack | {game_id}) if parent_game in by_gameobject else "."
        name, active = objects[game_id]
        name = godot_name(name)
        key = (parent, name)
        if key in used_names:
            name = godot_name(f"{name}_{game_id}")
        used_names[key] = True
        path = name if parent == "." else parent + "/" + name
        paths[game_id] = path
        lines.append(f'[node name={json.dumps(name, ensure_ascii=False)} type="Node3D" parent={json.dumps(parent, ensure_ascii=False)}]')
        if not active:
            lines.append("visible = false")
        x, y, z = pos
        if pos != (0, 0, 0):
            lines.append("position = " + vector((x, y, -z)))
        x, y, z, w = quat
        if quat != (0, 0, 0, 1):
            lines.append("quaternion = Quaternion(" + ", ".join(format(v, ".9g") for v in (-x, -y, z, w)) + ")")
        if scale != (1, 1, 1):
            lines.append("scale = " + vector(scale))
        lines.append("")
        return path
    for game_id in objects:
        if game_id in by_gameobject:
            emit(game_id)
    return ("\n".join(lines).rstrip() + "\n").encode("utf-8"), len(paths), warnings


@dataclass(frozen=True)
class Entry:
    source: str
    destination: str
    checksum: str
    size: int
    generated: bool
    original: Path | None = None
    content: bytes | None = None


def plan(source: Path, project: Path, engine: str | None = None) -> dict:
    source, project = source.resolve(), project.resolve()
    if not source.is_dir():
        raise ImportErrorDetail("Source project directory does not exist")
    if not (project / "project.godot").is_file():
        raise ImportErrorDetail("Target must be an existing Godot project (project.godot missing)")
    if source == project or project.is_relative_to(source) or source.is_relative_to(project):
        raise ImportErrorDetail("Source and target project directories must be separate")
    engine = engine or detect_engine(source)
    if engine not in ("unity", "unreal", "gamemaker", "defold", "generic"):
        raise ImportErrorDetail("Unknown engine")
    root = asset_root(source, engine).resolve()
    assets, warnings, unsupported = set(), [], Counter()
    for path in iter_files(root):
        suffix = path.suffix.lower()
        if suffix in PORTABLE:
            assets.add(path)
            if suffix == ".gltf":
                deps, problems = gltf_dependencies(path, root)
                assets.update(deps)
                warnings.extend(problems)
        elif engine == "unity" and suffix in (".unity", ".prefab"):
            pass
        else:
            unsupported[suffix or "(none)"] += 1
    entries = []
    def add(relative: Path, data: bytes | None, original: Path | None):
        destination = (Path("imported") / engine / relative).as_posix()
        if data is None:
            assert original is not None
            size, checksum = original.stat().st_size, file_digest(original)
        else:
            size, checksum = len(data), digest(data)
        entries.append(Entry(relative.as_posix(), destination, checksum, size, data is not None, original, data))
    for path in sorted(assets):
        add(path.relative_to(root), None, path)
    if engine == "unity":
        for path in iter_files(root):
            if path.suffix.lower() not in (".unity", ".prefab"):
                continue
            try:
                if path.stat().st_size > 16 * 1024 * 1024:
                    raise ImportErrorDetail("Unity text scene exceeds 16 MiB limit")
                result, count, notices = convert_unity_scene(path.read_text(encoding="utf-8-sig"))
                add(path.relative_to(root).with_suffix(".tscn"), result, None)
                warnings.extend(f"{path.relative_to(root)}: {notice}" for notice in notices)
                warnings.append(f"{path.relative_to(root)}: imported {count} placeholder nodes; scripts, renderers and behavior require manual porting")
            except (ImportErrorDetail, OSError, UnicodeError) as exc:
                warnings.append(f"{path.relative_to(root)}: skipped scene ({exc})")
    entries.sort(key=lambda e: e.destination)
    names = [e.destination.casefold() for e in entries]
    if len(set(names)) != len(names):
        raise ImportErrorDetail("Different source assets map to the same destination path")
    manifest = {"version": 1, "engine": engine, "assets": [
        {"source": e.source, "target": "res://" + e.destination,
         "sha256": e.checksum, "bytes": e.size, "generated": e.generated} for e in entries],
        "unsupported_extensions": dict(sorted(unsupported.items())), "warnings": sorted(warnings)}
    output = json.dumps(manifest, indent=2, ensure_ascii=False, sort_keys=True).encode("utf-8") + b"\n"
    manifest_path = (Path("imported") / engine / "import_manifest.json").as_posix()
    entries.append(Entry("(manifest)", manifest_path, digest(output), len(output), True, None, output))
    return {"engine": engine, "entries": entries, "report": manifest}


def apply_plan(result: dict, project: Path) -> tuple[int, int]:
    base = project.resolve()
    pending, skipped = [], 0
    for entry in result["entries"]:
        target = base / entry.destination
        if not target.resolve(strict=False).is_relative_to(base):
            raise ImportErrorDetail("Destination escaped the Godot project")
        if any(p.is_symlink() for p in (target, *target.parents) if p != base and p.is_relative_to(base)):
            raise ImportErrorDetail("Symlink in target path")
        if target.exists():
            if not target.is_file() or file_digest(target) != entry.checksum:
                raise ImportErrorDetail(f"Refusing to overwrite: {entry.destination}")
            skipped += 1
        else:
            pending.append((entry, target))
    created = []
    try:
        for entry, target in pending:
            target.parent.mkdir(parents=True, exist_ok=True)
            with target.open("xb") as output:
                created.append(target)
                if entry.content is not None:
                    output.write(entry.content)
                else:
                    assert entry.original is not None
                    with entry.original.open("rb") as input_file:
                        shutil.copyfileobj(input_file, output)
            if file_digest(target) != entry.checksum:
                raise ImportErrorDetail(f"Asset changed while copying: {entry.source}")
    except (OSError, ImportErrorDetail):
        for path in reversed(created):
            path.unlink(missing_ok=True)
        raise
    return len(pending), skipped


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="Unity/Unreal/GameMaker/Defold project or exported assets")
    parser.add_argument("godot_project", type=Path, help="existing Godot project root")
    parser.add_argument("--engine", choices=("unity", "unreal", "gamemaker", "defold", "generic"))
    parser.add_argument("--apply", action="store_true", help="write into res://imported/<engine> (dry-run by default)")
    args = parser.parse_args(argv)
    try:
        result = plan(args.source, args.godot_project, args.engine)
        written, unchanged = apply_plan(result, args.godot_project) if args.apply else (0, 0)
    except (ImportErrorDetail, OSError) as exc:
        print(f"engine import: {exc}", file=sys.stderr)
        return 2
    report = {**result["report"], "dry_run": not args.apply, "written": written,
              "unchanged": unchanged}
    print(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())