#!/bin/bash
# Downloads Poly Haven (CC0) terrain material maps at 1k into assets/textures/terrain_pbr/<id>/:
# diffuse, OpenGL normal, roughness and displacement (height, used for height-based layer blending).
#   game/tools/fetch_polyhaven_textures.sh            # every material below that is not there yet
#   game/tools/fetch_polyhaven_textures.sh forest_floor
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
PY="${PYTHON:-/usr/bin/python3}"
# The 9 layers the terrain already uses, plus richer ground variants.
MATERIALS="leafy_grass sparse_grass forest_leaves_02 brown_mud_leaves_01 grass_path_2 mossy_rock aerial_grass_rock coast_sand_01 snow_02
forest_floor forrest_ground_01 dry_decay_leaves rocky_terrain_02 dirt_floor forest_ground_04"
[ $# -gt 0 ] && MATERIALS="$*"
for id in $MATERIALS; do
  folder="$HERE/assets/textures/terrain_pbr/$id"
  if [ -f "$folder/${id}_disp.jpg" ]; then continue; fi
  mkdir -p "$folder"
  curl -sf -A "albion-after-asset-fetch" "https://api.polyhaven.com/files/$id" | "$PY" -I -c '
import json, sys, os, urllib.request
id, folder = sys.argv[1], sys.argv[2]
d = json.load(sys.stdin)
maps = {"Diffuse": "diff", "nor_gl": "nor_gl", "Rough": "rough", "Displacement": "disp"}
for key, suffix in maps.items():
    entry = d.get(key, {}).get("1k", {})
    info = entry.get("jpg") or entry.get("png")
    if not info:
        continue
    ext = ".jpg" if "jpg" in entry else ".png"
    request = urllib.request.Request(info["url"], headers={"User-Agent": "albion-after-asset-fetch"})
    with urllib.request.urlopen(request) as response, open(os.path.join(folder, id + "_" + suffix + ext), "wb") as out:
        out.write(response.read())
' "$id" "$folder"
  echo "fetched $id"
done
