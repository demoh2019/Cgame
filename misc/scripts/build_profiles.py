#!/usr/bin/env python3
"""Validated, repeatable Godot exports using project-local build profiles.

Uses only the standard library. Build profiles do not replace Godot's native
export presets; they select one and provide a repeatable output destination.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import json
from pathlib import Path
import re
import subprocess
import sys


class ProfileError(ValueError):
    """Invalid configuration or unsafe build destination."""


@dataclass(frozen=True)
class Profile:
    name: str
    preset: str
    mode: str
    output: Path


PROFILE_NAME = re.compile(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,63}\Z")
PRESET_SECTION = re.compile(r"\[preset\.\d+\]\Z")
WINDOWS_RESERVED = re.compile(r"(?i)(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\..*)?\Z")
EXPORT_SWITCHES = {"release": "--export-release", "debug": "--export-debug", "pack": "--export-pack"}


def unique_object(pairs: list[tuple[str, object]]) -> dict:
    result = {}
    for key, value in pairs:
        if key in result:
            raise ProfileError(f"Duplicate JSON key: {key}")
        result[key] = value
    return result


def object_fields(obj: object, keys: set[str], where: str) -> dict:
    if not isinstance(obj, dict) or set(obj) != keys:
        raise ProfileError(f"{where} must contain exactly: {', '.join(sorted(keys))}")
    return obj


def destination(project: Path, relative: str) -> Path:
    if not isinstance(relative, str) or not relative or "\\" in relative or "\x00" in relative:
        raise ProfileError("Output must be a non-empty POSIX relative path")
    parts = relative.split("/")
    if parts[0] != "builds" or len(parts) < 3 or any(p in ("", ".", "..") for p in parts):
        raise ProfileError("Output must be beneath builds/ without empty or dot components")
    for part in parts:
        if (any(c in part for c in '<>:"|?*') or part.endswith((".", " "))
                or WINDOWS_RESERVED.fullmatch(part)):
            raise ProfileError(f"Non-portable output path component: {part}")
    # Check every existing component, including the destination itself. Never
    # allow a symlink to divert a build outside the project directory.
    target = project
    for part in parts:
        target = target / part
        if target.is_symlink():
            raise ProfileError(f"Symlink in build output path: {target}")
    if target.exists() and not target.is_file():
        raise ProfileError(f"Build output is not a regular file: {target}")
    return target


def preset_names(project: Path) -> set[str]:
    config = project / "export_presets.cfg"
    if not config.is_file():
        raise ProfileError(f"Missing Godot export presets: {config}")
    names: set[str] = set()
    in_preset = False
    try:
        lines = config.read_text(encoding="utf-8-sig").splitlines()
    except (OSError, UnicodeError) as exc:
        raise ProfileError(f"Cannot read export presets: {exc}") from exc
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("["):
            in_preset = bool(PRESET_SECTION.fullmatch(stripped))
        elif in_preset and stripped.startswith("name="):
            try:
                name = json.loads(stripped.removeprefix("name=").strip())
            except json.JSONDecodeError as exc:
                raise ProfileError(f"Invalid export preset name: {stripped}") from exc
            if not isinstance(name, str) or not name or name in names:
                raise ProfileError("Empty or duplicate Godot export preset name")
            names.add(name)
    if not names:
        raise ProfileError("No named presets found in export_presets.cfg")
    return names


def load_profiles(project: Path, path: Path) -> dict[str, Profile]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=unique_object)
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise ProfileError(f"Cannot read build profiles: {exc}") from exc
    object_fields(data, {"version", "profiles"}, "Configuration")
    if type(data["version"]) is not int or data["version"] != 1:
        raise ProfileError("Unsupported build profile version (expected 1)")
    entries = data["profiles"]
    if not isinstance(entries, dict) or not entries:
        raise ProfileError("profiles must be a non-empty object")
    presets = preset_names(project)
    profiles: dict[str, Profile] = {}
    outputs: set[Path] = set()
    for name, raw in sorted(entries.items()):
        if not PROFILE_NAME.fullmatch(name):
            raise ProfileError(f"Invalid profile name: {name}")
        item = object_fields(raw, {"preset", "mode", "output"}, f"Profile {name}")
        if not isinstance(item["preset"], str) or item["preset"] not in presets:
            raise ProfileError(f"{name}: unknown export preset: {item['preset']}")
        if not isinstance(item["mode"], str) or item["mode"] not in EXPORT_SWITCHES:
            raise ProfileError(f"{name}: mode must be release, debug or pack")
        output = destination(project, item["output"])
        if item["mode"] == "pack" and output.suffix.lower() not in (".pck", ".zip"):
            raise ProfileError(f"{name}: pack output must end in .pck or .zip")
        if output in outputs:
            raise ProfileError(f"Multiple profiles write to: {output}")
        outputs.add(output)
        profiles[name] = Profile(name, item["preset"], item["mode"], output)
    return profiles


def command_for(project: Path, profile: Profile, godot: str) -> list[str]:
    return [godot, "--headless", "--path", str(project), EXPORT_SWITCHES[profile.mode],
            profile.preset, str(profile.output)]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("list", "validate", "plan", "build"))
    parser.add_argument("profile", nargs="?", help="Profile name (required for build)")
    parser.add_argument("--project", default=".", help="Godot project directory")
    parser.add_argument("--config", default="build_profiles.json", help="Profiles JSON, relative to project")
    parser.add_argument("--godot", default="godot", help="Godot editor executable")
    parser.add_argument("--overwrite", action="store_true", help="Allow replacing an existing build")
    args = parser.parse_args(argv)
    project = Path(args.project).resolve()
    if not (project / "project.godot").is_file():
        parser.error(f"Not a Godot project: {project}")
    path = Path(args.config)
    if not path.is_absolute():
        path = project / path
    try:
        profiles = load_profiles(project, path)
        if args.profile and args.profile not in profiles:
            raise ProfileError(f"Unknown build profile: {args.profile}")
        if args.command == "build" and not args.profile:
            raise ProfileError("build requires a profile name")
        if args.command == "validate":
            print(f"Validated {len(profiles)} build profiles")
        elif args.command == "list":
            for profile in profiles.values():
                print(f"{profile.name}: {profile.mode}, {profile.preset} -> {profile.output.relative_to(project)}")
        elif args.command == "plan":
            for profile in (profiles[args.profile],) if args.profile else profiles.values():
                print(json.dumps(command_for(project, profile, args.godot), ensure_ascii=False))
        else:
            profile = profiles[args.profile]
            # Recheck immediately before export, including an existing destination.
            output = destination(project, str(profile.output.relative_to(project).as_posix()))
            if output.exists() and not args.overwrite:
                raise ProfileError("Build exists; use --overwrite to replace it")
            try:
                output.parent.mkdir(parents=True, exist_ok=True)
            except OSError as exc:
                raise ProfileError(f"Cannot create build directory: {exc}") from exc
            # Recheck symlinks after creating folders, before running Godot.
            destination(project, str(output.relative_to(project).as_posix()))
            try:
                return subprocess.run(command_for(project, profile, args.godot), check=False, cwd=project).returncode
            except OSError as exc:
                raise ProfileError(f"Cannot launch Godot: {exc}") from exc
    except ProfileError as exc:
        print(f"build_profiles: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
