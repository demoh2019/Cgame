#!/usr/bin/env python3
"""Install a user-licensed Wild Grass archive for local Albion After rendering.

Usage:
    python3 game/tools/install_user_wild_grass.py /path/to/wild_grass_vlkhcbxia_ue_low.zip

The source pack is not checked into Git: Fab/Quixel asset licenses do not
generally allow redistributing standalone source asset files publicly.
Only fixed expected archive paths are extracted (no ZIP path traversal).
"""

from __future__ import annotations

import argparse
import json
import shutil
import zipfile
from pathlib import Path

GAME = Path(__file__).resolve().parents[1]
TARGET = GAME / "assets" / "models" / "community_grass" / "wild_grass"
FILES = (
    "standard/vlkhcbxia_tier_3_nonUE.gltf",
    "vlkhcbxia_tier_3.bin",
    "Textures/T_vlkhcbxia_1K_B-O.png",
    "Textures/T_vlkhcbxia_1K_N.jpg",
    "Textures/T_vlkhcbxia_1K_ORT.jpg",
    "Textures/T_vlkhcbxia_1K_Billboard_B-O.png",
    "Textures/T_vlkhcbxia_1K_Billboard_N-T.png",
    "vlkhcbxia.json",
)


def install(archive: Path) -> Path:
    with zipfile.ZipFile(archive) as source:
        missing = sorted(set(FILES).difference(source.namelist()))
        if missing:
            raise ValueError("Missing files in archive: " + ", ".join(missing))
        gltf = json.loads(source.read(FILES[0]))
        mesh_names = {m.get("name", "") for m in gltf.get("meshes", [])}
        required = {f"SM_vlkhcbxia_Var{variant}_LOD1" for variant in "ABCDEFGH"}
        if not required.issubset(mesh_names):
            raise ValueError("The archive does not contain all eight LOD1 grass variants")
        # Never call ZipFile.extractall() on an untrusted ZIP.
        for member in FILES:
            destination = TARGET / member
            destination.parent.mkdir(parents=True, exist_ok=True)
            with source.open(member) as from_zip, destination.open("wb") as to_file:
                shutil.copyfileobj(from_zip, to_file)
    return TARGET


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path, help="User-provided Wild Grass ZIP")
    args = parser.parse_args()
    target = install(args.archive)
    print(f"Installed grass model pack to: {target}")
    print("Open the game project in Cgame/Godot once to import the glTF + textures.")
    print("The active GroundPlants meadow now uses 3D scans nearby and old cards only farther away.")
