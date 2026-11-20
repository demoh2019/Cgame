#!/bin/bash
# Poly Haven plant glTFs reference a JPEG diffuse with no alpha; the leaf mask is a separate "Alpha" map.
# This fetches each plant's 1k Alpha (and dry diffuse when offered) and writes RGBA PNGs next to the
# textures: <id>_diff_alpha.png (and <id>_dry_alpha.png) used by scripts/client/ground_plants.gd.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
PY="${PYTHON:-/usr/bin/python3}"
PLANTS="grass_medium_01 grass_medium_02 grass_bermuda_01 dandelion_01 celandine_01 flower_heliophila nettle_plant weed_plant_02
shrub_sorrel_01 periwinkle_plant moss_01 fern_02 shrub_02 shrub_03 shrub_04 flower_empodium flower_gazania flower_ursinia flower_stinkkruid"
[ $# -gt 0 ] && PLANTS="$*"
for id in $PLANTS; do
  folder="$HERE/assets/models/polyhaven/$id/textures"
  [ -f "$folder/${id}_diff_alpha.png" ] && continue
  tmp="$(mktemp -d)"
  curl -sf -A "albion-after-asset-fetch" "https://api.polyhaven.com/files/$id" | "$PY" -I -c '
import json, sys, os, urllib.request
d = json.load(sys.stdin); out = sys.argv[1]
for key, name in (("Alpha", "alpha.jpg"), ("Diffuse", "diff.jpg"), ("dry_diff", "dry.jpg")):
    info = d.get(key, {}).get("1k", {}).get("jpg")
    if info:
        req = urllib.request.Request(info["url"], headers={"User-Agent": "albion-after-asset-fetch"})
        with urllib.request.urlopen(req) as r, open(os.path.join(out, name), "wb") as f:
            f.write(r.read())
' "$tmp"
  if [ -f "$tmp/alpha.jpg" ] && [ -f "$tmp/diff.jpg" ]; then
    magick "$tmp/diff.jpg" \( "$tmp/alpha.jpg" -colorspace gray \) -alpha off -compose CopyOpacity -composite "$folder/${id}_diff_alpha.png"
    if [ -f "$tmp/dry.jpg" ]; then
      magick "$tmp/dry.jpg" \( "$tmp/alpha.jpg" -colorspace gray \) -alpha off -compose CopyOpacity -composite "$folder/${id}_dry_alpha.png"
    fi
    echo "alpha $id"
  else
    echo "no alpha map for $id"
  fi
  rm -rf "$tmp"
done
