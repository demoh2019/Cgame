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
mkdir -p "$DEST/characters" "$DEST/animations" "$DEST/nature" "$DEST/village"

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
echo "Imported into $DEST:"
for d in characters animations nature village; do printf "  %-11s %s files\n" "$d" "$(ls "$DEST/$d" | wc -l | tr -d ' ')"; done
