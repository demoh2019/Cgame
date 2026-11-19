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



UNITY_SPRITE_EXTENSIONS = frozenset({".png", ".jpg", ".jpeg", ".webp", ".bmp", ".tga"})
GUID = re.compile(r"^guid:\s*([0-9a-fA-F]{32})\s*$", re.MULTILINE)


def unity_texture_guids(root: Path, assets: set[Path]) -> tuple[dict[str, tuple[str, float]], list[str]]:
    """Map only unambiguous Unity sprite texture GUIDs to imported Godot paths.

    Multi-sprite texture atlases have subasset file IDs/pivots and cannot be safely
    represented as a whole-image Sprite3D, so they are intentionally skipped.
    """
    mapping, ambiguous, warnings = {}, set(), []
    for image in sorted(assets):
        if image.suffix.lower() not in UNITY_SPRITE_EXTENSIONS:
            continue
        meta = image.with_name(image.name + ".meta")
        if meta.is_symlink() or not meta.is_file():
            continue
        try:
            if meta.stat().st_size > 256 * 1024:
                warnings.append(f"{meta.relative_to(root)}: oversized Unity texture metadata skipped")
                continue
            data = meta.read_text(encoding="utf-8-sig")
        except (OSError, UnicodeError):
            warnings.append(f"{meta.relative_to(root)}: unreadable Unity texture metadata")
            continue
        matches = GUID.findall(data)
        if len(matches) != 1:
            warnings.append(f"{meta.relative_to(root)}: invalid Unity texture GUID")
            continue
        guid = matches[0].lower()
        if re.search(r"^\s*spriteMode:\s*2\s*$", data, re.MULTILINE):
            warnings.append(f"{meta.relative_to(root)}: multi-sprite atlas requires manual slicing")
            ambiguous.add(guid)
            mapping.pop(guid, None)
            continue
        path = "res://" + (Path("imported/unity") / image.relative_to(root)).as_posix()
        ppu = 100.0
        ppu_match = re.search(r"^\s*spritePixelsToUnits:\s*(\S+)", data, re.MULTILINE)
        if ppu_match:
            try:
                ppu = float(ppu_match.group(1))
                if not 0.01 <= ppu <= 10_000:
                    raise ValueError("invalid Unity pixels per unit")
            except ValueError:
                warnings.append(f"{meta.relative_to(root)}: invalid sprite pixels-per-unit; assuming 100")
                ppu = 100.0
        if guid in mapping or guid in ambiguous:
            warnings.append(f"{meta.relative_to(root)}: duplicate Unity texture GUID; texture skipped")
            ambiguous.add(guid)
            mapping.pop(guid, None)
            continue
        mapping[guid] = (path, ppu)
    return mapping, warnings


def unity_color(document: str) -> tuple[float, float, float, float]:
    raw = field(document, "m_Color")
    out = []
    for key in "rgba":
        match = re.search(r"(?:^|[,{}])\s*" + key + r":\s*(" + NUMBER + r")(?=\s*[,}]|$)", raw)
        if not match:
            return (1, 1, 1, 1)
        value = float(match.group(1))
        if not 0 <= value <= 1:
            return (1, 1, 1, 1)
        out.append(value)
    return tuple(out)


def unity_number(document: str, *keys: str, default: float) -> float:
    for key in keys:
        raw = field(document, key)
        try:
            value = float(raw)
            if -1e12 < value < 1e12:
                return value
        except ValueError:
            pass
    return default


def convert_unity_scene(contents: str, textures: dict[str, str | tuple[str, float]] | None = None) -> tuple[bytes, int, list[str]]:
    """Convert Unity text scene geometry plus a limited subset of visual nodes.

    Supported components: 3D Transform (4), SpriteRenderer (212) when its texture
    GUID is a safe direct sprite, and Camera (20). Game behavior isn't converted.
    """
    sections = list(HEADER.finditer(contents))
    if not sections or not contents.lstrip().startswith(("%YAML", "--- !u!")):
        raise ImportErrorDetail("Not a Unity text-serialized scene")
    textures = textures or {}
    objects, transforms, sprites, cameras, unsupported = {}, {}, [], [], Counter()
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
        elif type_id == "212":
            sprites.append((file_id, ref(body, "m_GameObject"), body))
        elif type_id == "20":
            cameras.append((file_id, ref(body, "m_GameObject"), body))
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

    paths, lines = {}, ['[node name="ImportedUnityScene" type="Node3D"]', ""]
    used_names: set[tuple[str, str]] = set()
    external: dict[str, str] = {}

    def unique_name(parent: str, name: str, fallback: str) -> str:
        name = godot_name(name)
        original = name
        index = 1
        while (parent, name) in used_names:
            name = godot_name(f"{original}_{fallback}_{index}")
            index += 1
        used_names.add((parent, name))
        return name

    def emit(game_id: str, stack: frozenset[str] = frozenset()) -> str:
        if game_id in paths:
            return paths[game_id]
        if game_id in stack:
            raise ImportErrorDetail("Cyclic Unity Transform hierarchy")
        tid, father, pos, quat, scale = by_gameobject[game_id]
        parent_game = transforms.get(father, (None,))[0] if father in transforms else None
        parent = emit(parent_game, stack | {game_id}) if parent_game in by_gameobject else "."
        raw_name, active = objects[game_id]
        # Keep legacy name suffixes for duplicate Unity GameObjects.
        name = godot_name(raw_name)
        if (parent, name) in used_names:
            name = godot_name(f"{name}_{game_id}")
        name = unique_name(parent, name, game_id)
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

    for file_id, game_id, body in sprites:
        if game_id not in paths:
            warnings.append(f"SpriteRenderer {file_id}: GameObject has no converted Transform")
            continue
        sprite = field(body, "m_Sprite")
        found = re.search(r"\bguid:\s*([0-9a-fA-F]{32})\b", sprite)
        source_texture = textures.get(found.group(1).lower()) if found else None
        if not source_texture:
            if ref(body, "m_Sprite") != "0":
                warnings.append(f"SpriteRenderer {file_id}: sprite texture GUID unavailable; renderer omitted")
            continue
        texture, ppu = ((source_texture, 100.0) if isinstance(source_texture, str)
                        else source_texture)
        parent = paths[game_id]
        name = unique_name(parent, "Sprite", file_id)
        resource_id = external.setdefault(texture, str(len(external) + 1))
        lines.append(f'[node name={json.dumps(name)} type="Sprite3D" parent={json.dumps(parent, ensure_ascii=False)}]')
        lines.append(f'texture = ExtResource("{resource_id}")')
        if ppu != 100.0:
            lines.append("pixel_size = " + format(1 / ppu, ".9g"))
        if field(body, "m_Enabled", "1") == "0":
            lines.append("visible = false")
        if field(body, "m_FlipX", "0") == "1":
            lines.append("flip_h = true")
        if field(body, "m_FlipY", "0") == "1":
            lines.append("flip_v = true")
        color = unity_color(body)
        if color != (1, 1, 1, 1):
            lines.append("modulate = Color(" + ", ".join(format(v, ".9g") for v in color) + ")")
        lines.append("")
        if field(body, "m_DrawMode", "0") not in ("0", ""):
            warnings.append(f"SpriteRenderer {file_id}: sliced/tiled draw mode requires manual porting")
        if field(body, "m_SortingOrder", "0") not in ("0", ""):
            warnings.append(f"SpriteRenderer {file_id}: sorting order requires manual porting")

    for file_id, game_id, body in cameras:
        if game_id not in paths:
            warnings.append(f"Camera {file_id}: GameObject has no converted Transform")
            continue
        parent = paths[game_id]
        name = unique_name(parent, "Camera", file_id)
        lines.append(f'[node name={json.dumps(name)} type="Camera3D" parent={json.dumps(parent, ensure_ascii=False)}]')
        if field(body, "m_Enabled", "1") == "0" or not objects[game_id][1]:
            lines.append("current = false")
        ortho = field(body, "orthographic", field(body, "m_Orthographic", "0")) == "1"
        if ortho:
            lines.append("projection = 1")
            size = unity_number(body, "orthographic size", "m_OrthographicSize", default=5)
            if size > 0:
                lines.append("size = " + format(size * 2, ".9g"))
        else:
            fov = unity_number(body, "field of view", "m_FieldOfView", default=75)
            if 1 < fov < 179:
                lines.append("fov = " + format(fov, ".9g"))
        near = unity_number(body, "near clip plane", "m_NearClipPlane", default=0.05)
        far = unity_number(body, "far clip plane", "m_FarClipPlane", default=4000)
        if 0 < near < far:
            lines.append("near = " + format(near, ".9g"))
            lines.append("far = " + format(far, ".9g"))
        lines.append("")
        warnings.append(f"Camera {file_id}: viewport, background and render settings require manual porting")

    prefix = [f"[gd_scene load_steps={1 + len(external)} format=3]", ""]
    for path, resource_id in external.items():
        prefix.append(f'[ext_resource type="Texture2D" path={json.dumps(path, ensure_ascii=False)} id="{resource_id}"]')
    if external:
        prefix.append("")
    return ("\n".join(prefix + lines).rstrip() + "\n").encode("utf-8"), len(paths), warnings


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
        textures, notices = unity_texture_guids(root, assets)
        warnings.extend(notices)
        for path in iter_files(root):
            if path.suffix.lower() not in (".unity", ".prefab"):
                continue
            try:
                if path.stat().st_size > 16 * 1024 * 1024:
                    raise ImportErrorDetail("Unity text scene exceeds 16 MiB limit")
                result, count, notices = convert_unity_scene(path.read_text(encoding="utf-8-sig"), textures)
                add(path.relative_to(root).with_suffix(".tscn"), result, None)
                warnings.extend(f"{path.relative_to(root)}: {notice}" for notice in notices)
                warnings.append(f"{path.relative_to(root)}: imported {count} GameObject nodes; unsupported components and game behavior require manual porting")
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