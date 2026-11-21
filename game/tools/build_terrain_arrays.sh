#!/bin/bash
# Builds the terrain layer arrays as 4x4 grids imported by Godot as VRAM-compressed Texture2DArrays
# (see the .import files beside them): albedo at 2048 px and normal at 1024 px per layer (Poly Haven 2k, CC0, for the
# natural layers; the paved layers are upscaled from assets/textures/terrain), and displacement at 512 px.
# Slice order follows ChunkView.TERRAIN_LAYERS; slices 13-15 repeat the last layer (unused).
#   game/tools/build_terrain_arrays.sh [folder with <id>_diff.jpg / <id>_nor_gl.jpg at 2k]
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${1:-}"
PY="${PYTHON:-/usr/bin/python3}"
LAYERS="lush:forrest_ground_01 dry:aerial_rocks_01 forest:forest_leaves_04 swamp:brown_mud_03 road:rocky_trail cliff:cliff_side mountain:aerial_rocks_02 sand:coast_sand_02 snow:snow_02 asphalt: concrete: brick: plank:"
TMP="$(mktemp -d)"
if [ -z "$SRC" ]; then
  SRC="$TMP/src"; mkdir -p "$SRC"
  for pair in $LAYERS; do
    id="${pair#*:}"; [ -z "$id" ] && continue
    curl -sf -A "albion-after-asset-fetch" "https://api.polyhaven.com/files/$id" | "$PY" -I -c '
import json, sys, urllib.request
d = json.load(sys.stdin); id, out = sys.argv[1], sys.argv[2]
for key, suffix in (("Diffuse", "diff"), ("nor_gl", "nor_gl")):
    req = urllib.request.Request(d[key]["2k"]["jpg"]["url"], headers={"User-Agent": "albion-after-asset-fetch"})
    open(out + "/" + id + "_" + suffix + ".jpg", "wb").write(urllib.request.urlopen(req).read())
' "$id" "$SRC"
  done
fi
albedo=(); normal=(); height=()
for pair in $LAYERS; do
  layer="${pair%%:*}"; id="${pair#*:}"
  if [ -n "$id" ]; then
    albedo+=("$SRC/${id}_diff.jpg"); normal+=("$SRC/${id}_nor_gl.jpg")
    height+=("$HERE/assets/textures/terrain_pbr/$id/${id}_disp.jpg")
  else
    albedo+=("$HERE/assets/textures/terrain/${layer}_diff.jpg"); normal+=("$HERE/assets/textures/terrain/${layer}_nor_gl.jpg")
    height+=("xc:gray50")
  fi
done
last=$(( ${#albedo[@]} - 1 ))
for i in 13 14 15; do albedo+=("${albedo[$last]}"); normal+=("${normal[$last]}"); height+=("${height[$last]}"); done
OUT="$HERE/assets/textures/terrain_arrays"
mkdir -p "$OUT"
montage "${albedo[@]}" -resize 2048x2048\! -tile 4x4 -geometry +0+0 -quality 92 "$OUT/terrain_albedo_array.jpg"
montage "${normal[@]}" -resize 1024x1024\! -tile 4x4 -geometry +0+0 -quality 93 "$OUT/terrain_normal_array.jpg"
montage "${height[@]}" -resize 512x512\! -tile 4x4 -geometry +0+0 -colorspace gray -quality 92 "$OUT/terrain_height_array.jpg"
rm -rf "$TMP"
echo "built terrain arrays in $OUT"
