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
forest_floor forrest_ground_01 dry_decay_leaves rocky_terrain_02 dirt_floor forest_ground_04
sandstone_cracks cliff_side rock_face rock_face_03 rock_face_04 dark_rock lichen_rock rock_pitted_mossy rock_boulder_dry rock_boulder_cracked rocky_terrain rocky_terrain_03 rocky_trail rock_ground rocks_ground_01 rocks_ground_02 rocks_ground_03 rocks_ground_04 rocks_ground_05 rocks_ground_06 rocks_ground_08 rocks_ground_09 gravel_ground_01 gravelly_sand sandy_gravel_02 coast_sand_02 coast_sand_03 coast_sand_04 coast_sand_05 coast_sand_rocks_02 coast_land_rocks_01 seaside_rock aerial_rocks_01 aerial_rocks_02 aerial_sand aerial_ground_rock aerial_mud_1 brown_mud brown_mud_02 brown_mud_03 brown_mud_dry brown_mud_rocks_01 dry_ground_01 dry_ground_rocks mud_cracked_dry_03 red_dirt_mud_01 red_laterite_soil_stones red_mud_stones forest_ground_05 forest_ground_06 forest_leaves_03 forest_leaves_04 forrest_ground_03 forrest_sand_01 leaves_forest_ground leaf_scattered_gravel grass_ground grass_path_3 burned_ground_01 river_small_rocks dry_river_pebbles dry_riverbed_rock pebble_ground_01 tiger_rock worn_rock_natural_01"
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
