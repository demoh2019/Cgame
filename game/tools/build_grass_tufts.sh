#!/bin/bash
# Builds assets/models/polyhaven/grass_medium_01/textures/grass_tufts_atlas.png: the five dense grass tufts
# photographed in Poly Haven's grass_medium_01 atlas (CC0), cut from the 4k diffuse + alpha, each kept to its
# largest alpha component (no stray atlas pieces), 1024x512 per tuft, stacked vertically (1024x2560).
# Used by scripts/client/ground_plants.gd for the grass carpet cards. Needs ImageMagick.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
PY="${PYTHON:-/usr/bin/python3}"
TMP="$(mktemp -d)"
curl -sf -A "albion-after-asset-fetch" "https://api.polyhaven.com/files/grass_medium_01" | "$PY" -I -c '
import json, sys, os, urllib.request
d = json.load(sys.stdin); out = sys.argv[1]
for key, name in (("Diffuse", "diff.jpg"), ("Alpha", "alpha.jpg")):
    req = urllib.request.Request(d[key]["4k"]["jpg"]["url"], headers={"User-Agent": "albion-after-asset-fetch"})
    with urllib.request.urlopen(req) as r, open(os.path.join(out, name), "wb") as f:
        f.write(r.read())
' "$TMP"
# Tuft rectangles in the 4k atlas (x, y, w, h).
REGIONS="1160x448+840+3160 880x424+2480+3136 680x408+120+3600 1040x440+1024+3600 960x512+2320+3560"
i=0
for r in $REGIONS; do
  magick "$TMP/diff.jpg" -crop "$r" +repage -resize 1024x512\! "$TMP/c$i.png"
  magick "$TMP/alpha.jpg" -colorspace gray -crop "$r" +repage -resize 1024x512\! "$TMP/a$i.png"
  magick "$TMP/a$i.png" -threshold 25% -morphology Dilate Disk:6 -define connected-components:keep-top=1 \
    -define connected-components:mean-color=true -connected-components 8 -threshold 50% "$TMP/m$i.png"
  magick "$TMP/a$i.png" "$TMP/m$i.png" -compose Darken -composite "$TMP/f$i.png"
  magick "$TMP/c$i.png" -alpha off "$TMP/f$i.png" -compose CopyOpacity -composite "$TMP/t$i.png"
  i=$((i + 1))
done
magick "$TMP/t0.png" "$TMP/t1.png" "$TMP/t2.png" "$TMP/t3.png" "$TMP/t4.png" -append +repage \
  "PNG32:$HERE/assets/models/polyhaven/grass_medium_01/textures/grass_tufts_atlas.png"
rm -rf "$TMP"
echo "built grass_tufts_atlas.png"
