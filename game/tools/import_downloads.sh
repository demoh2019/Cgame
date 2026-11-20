#!/bin/bash
# Copies the model packs you downloaded (default: ~/Downloads) into game/assets/packs, where the game finds them.
# Nothing here is committed: the Quaternius packs (QAL licence) and the EmacEArt pack forbid redistributing the
# assets themselves, so every developer imports their own copy. Without the packs the game falls back to the
# small Kenney set in assets/kenney.
#   game/tools/import_downloads.sh [downloads-dir]
set -euo pipefail
SRC="${1:-$HOME/Downloads}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$HERE/assets/packs"
TMP="$(mktemp -d)"
trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
mkdir -p "$DEST/characters" "$DEST/outfits" "$DEST/music" "$DEST/animations" "$DEST/nature" "$DEST/village" "$DEST/highlands" "$DEST/dungeon" "$DEST/props" "$DEST/loose"

extract() { # zip-name
  if [ -f "$SRC/$1" ]; then unzip -q -o "$SRC/$1" -d "$TMP/$2"; return 0; fi
  echo "missing: $SRC/$1"; return 1
}

if extract "Characters - Fantasy Races Kit[Standard].zip" chars; then
  cp "$TMP"/chars/*/Exports/"GLB (Godot-Unreal)"/*.glb "$DEST/characters/"
fi
if extract "Universal Animation Library[Standard].zip" ual1; then
  cp "$TMP"/ual1/*/Unreal-Godot/UAL1_Standard.glb "$DEST/animations/"
fi
if extract "Universal Animation Library 2[Standard].zip" ual2; then
  cp "$TMP"/ual2/*/Unreal-Godot/UAL2_Standard.glb "$DEST/animations/"
fi
if extract "Stylized Nature MegaKit[Standard].zip" nature; then
  cp "$TMP"/nature/glTF/* "$DEST/nature/"
fi
if extract "glb.zip" village; then
  cp "$TMP"/village/glb/*.glb "$DEST/village/"
fi
# Highlands fantasy buildings (FBX): only the diffuse atlases, shrunk from 4096 to 2048 pixels (the normal maps weigh 70 MB each).
if extract "HighLandsFantasyBuildings.zip" hl; then
  for fbx in $(find "$TMP/hl" -name "*.fbx"); do cp "$fbx" "$DEST/highlands/"; done
  for tex in $(find "$TMP/hl" -name "*diffuse.png"); do cp "$tex" "$DEST/highlands/"; done
  PY="${PYTHON:-python3}"
  "$PY" - "$DEST/highlands" <<'PYEOF' || echo "  (could not shrink the Highlands textures: install Pillow or set PYTHON; they stay 4096 px)"
import glob, sys
from PIL import Image
for path in glob.glob(sys.argv[1] + "/*diffuse.png"):
    image = Image.open(path)
    if image.size[0] > 2048:
        image.resize((2048, 2048), Image.LANCZOS).save(path, optimize=True)
PYEOF
fi
# KayKit dungeon (CC0): walls, floors, stairs, pillars, tables, chests, torches, banners, barrels, crates, bones.
if extract "KayKit_Dungeon_Pack_1.1_FREE.zip" dungeon; then
  cp "$TMP"/dungeon/*/Assets/gltf/* "$DEST/dungeon/"
fi
# FreeVersion (RAR): market stalls, huts, bridges, fences, vases, braziers. One textured glb holds them all.
if [ -f "$SRC/FreeVersion.rar" ] && command -v unar >/dev/null; then
  unar -q -o "$TMP/props" "$SRC/FreeVersion.rar" >/dev/null && cp "$TMP"/props/FreeVersion/AllModelsInOne/AllAssets_with_texture.glb "$DEST/props/" || true
fi
# Universal Base Characters and Modular Character Outfits - Fantasy (Quaternius, CC0): human survivors in clothes, on the
# same skeleton as the animation library. Base bodies, hair rigged to the head bone, and the four complete outfits.
if extract "Universal Base Characters[Standard].zip" ubc; then
  cp "$TMP"/ubc/*/"Base Characters/Godot - UE"/* "$DEST/outfits/"
  cp "$TMP"/ubc/*/Hairstyles/"Rigged to Head Bone"/"glTF (Godot -Unreal)"/* "$DEST/outfits/"
fi
if extract "Modular Character Outfits - Fantasy[Standard].zip" outfits; then
  cp "$TMP"/outfits/*/Exports/"glTF (Godot-Unreal)"/Outfits/* "$DEST/outfits/"
  # The separate pieces too, for mixed outfits (the same textures as the whole ones).
  cp "$TMP"/outfits/*/Exports/"glTF (Godot-Unreal)"/"Modular Parts"/*.gltf "$TMP"/outfits/*/Exports/"glTF (Godot-Unreal)"/"Modular Parts"/*.bin "$DEST/outfits/"
fi
# Their textures are 2048-4096 px: far more than a character a few dozen pixels tall needs, and loading them mid-game
# stalls the client long enough to drop the connection. Colour and ORM maps go to 1024 px, normal maps to 512 px.
shrink_outfits() {
  for tex in "$DEST"/outfits/*.png; do
    case "$tex" in *Normal*) size=512 ;; *) size=1024 ;; esac
    if command -v sips >/dev/null; then sips -Z "$size" "$tex" >/dev/null
    else "${PYTHON:-python3}" -c 'import sys; from PIL import Image; i=Image.open(sys.argv[1]); s=int(sys.argv[2]); i.thumbnail((s, s)); i.save(sys.argv[1])' "$tex" "$size" || true; fi
  done
}
[ -d "$DEST/outfits" ] && shrink_outfits
# Music: Fantasy RPG Music Vol. 2 (its licence allows use in games, not passing the files on). The mp3 versions of the
# tracks scripts/client/audio.gd plays by day, at night and in a fight.
if extract "Fantasy RPG Music Vol. 2.zip" music; then
  for track in "Light Ambient 1 (Loop)" "Light Ambient 2 (Loop)" "Light Ambient 3 (Loop)" "Night Ambient 2 (Loop)" "Night Ambient 3 (Loop)" "Action 1 (Loop)" "Action 2 (Loop)" Death Victory Complete; do
    cp "$TMP/music/mp3/$track.mp3" "$DEST/music/" || true
  done
fi
# Single models and model collections you saved from the web (glb): the ones the game uses.
for name in stone_pack stylized_stones_minipack stylized_rocks_formation_asset_pack stylized_hand_painted_trees hand_painted_grasses flowers_pack_1 stylized_flowers_and_dandelions aloe_plant_set rock_and_plants crystal toon_style_-_crystal low_poly_treasure_chest low_poly_tree_log_and_stump the_ancient_mystic_stone low_poly_hand_painted_dungeon_plinth stylized_handpainted_foliage forest_scene hand_painted_forest; do
  [ -f "$SRC/$name.glb" ] && cp "$SRC/$name.glb" "$DEST/loose/" || true
done
echo "Imported into $DEST:"
for d in characters outfits music animations nature village highlands dungeon props loose; do printf "  %-11s %s files\n" "$d" "$(ls "$DEST/$d" | wc -l | tr -d ' ')"; done
