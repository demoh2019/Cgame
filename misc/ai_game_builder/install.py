#!/usr/bin/env python3
"""Install the AI Game Builder EditorPlugin into an existing Godot 4 project.

No dependencies other than Python 3.10+. Never edits project.godot automatically.
"""
from __future__ import annotations

import argparse
from pathlib import Path
import shutil
import sys

ADDON = Path(__file__).resolve().parent / "addons" / "ai_game_builder"


def install(project: Path, *, force: bool = False) -> Path:
    project = project.expanduser().resolve()
    if not project.is_dir() or not (project / "project.godot").is_file():
        raise ValueError(f"Not an existing Godot project (project.godot missing): {project}")
    if not ADDON.is_dir() or not (ADDON / "plugin.cfg").is_file():
        raise FileNotFoundError(f"Addon files are missing: {ADDON}")
    destination = project / "addons" / "ai_game_builder"
    if destination.exists() and not force:
        raise FileExistsError(f"Destination exists (use --force after backup): {destination}")
    if destination.is_symlink():
        raise ValueError("Refusing to modify a symlinked addon directory")
    destination.parent.mkdir(parents=True, exist_ok=True)
    # Copy into a temporary sibling before replacing the destination to avoid
    # exposing half-copied files on interrupted runs.
    temporary = destination.with_name(destination.name + ".installing")
    if temporary.exists() or temporary.is_symlink():
        raise FileExistsError(f"Temporary destination already exists: {temporary}")
    try:
        shutil.copytree(ADDON, temporary)
        if destination.exists():
            shutil.rmtree(destination)
        temporary.rename(destination)
    finally:
        if temporary.exists():
            shutil.rmtree(temporary)
    return destination


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, required=True, help="Godot project directory")
    parser.add_argument("--force", action="store_true", help="Replace an existing addon folder")
    args = parser.parse_args(argv)
    try:
        dest = install(args.project, force=args.force)
    except (OSError, ValueError) as exc:
        print(f"Installation failed: {exc}", file=sys.stderr)
        return 1
    print(f"Installed at {dest}")
    print("Enable AI Game Builder in Project > Project Settings > Plugins.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
