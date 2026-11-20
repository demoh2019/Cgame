#!/bin/bash
# Downloads the Poly Haven (CC0) models used by the game: the 1k glTF of each, with its textures shrunk to 512 px.
# The repository keeps these small sources plus the meshes baked from them by tools/bake_polyhaven.gd.
#   game/tools/fetch_polyhaven.sh            # every model below that is not there yet
#   game/tools/fetch_polyhaven.sh boulder_01 # only these
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
PY="${PYTHON:-/usr/bin/python3}"
MODELS="stone_fire_pit wooden_lantern_01 boulder_01 dead_tree_trunk_02 tree_stump_01 rock_moss_set_01 rock_moss_set_02
wooden_crate_01 horse_statue_01 wooden_bucket_01 namaqualand_boulder_02 wine_barrel_01 wooden_barrels_01
Barrel_01 barrel_03 barrel_stove metal_jerrycan metal_jerrycan_green old_military_crate wooden_military_crate ammo_box
old_tyre rusted_wheel_rim_01 concrete_road_barrier metal_trash_can trashbag propane_tank portable_generator street_lamp_01
fire_hydrant wooden_picnic_table plastic_crate_01 cardboard_box_01 wooden_crate_02 worn_metal_rack tool_cart
painted_wooden_bench rock_07 rock_09 namaqualand_boulder_04 tree_stump_02 dead_tree_trunk"
[ $# -gt 0 ] && MODELS="$*"
for id in $MODELS; do
  folder="$HERE/assets/models/polyhaven/$id"
  if [ -f "$folder/$id.gltf" ]; then continue; fi
  mkdir -p "$folder"
  curl -sf -A "albion-after-asset-fetch" "https://api.polyhaven.com/files/$id" | "$PY" -I -c '
import json, sys, os, urllib.request
id, folder = sys.argv[1], sys.argv[2]
g = json.load(sys.stdin)["gltf"]["1k"]["gltf"]
def fetch(url, path):
    request = urllib.request.Request(url, headers={"User-Agent": "albion-after-asset-fetch"})
    with urllib.request.urlopen(request) as response, open(path, "wb") as out:
        out.write(response.read())
fetch(g["url"], os.path.join(folder, id + ".gltf"))
for rel, info in g.get("include", {}).items():
    path = os.path.normpath(os.path.join(folder, rel))
    if not path.startswith(os.path.normpath(folder) + os.sep):
        raise SystemExit("unsafe path " + rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fetch(info["url"], path)
' "$id" "$folder"
  # 512 px textures are plenty for props seen from the top-down camera.
  if command -v sips >/dev/null; then
    find "$folder" \( -name "*.jpg" -o -name "*.png" \) -exec sips -Z 512 {} \; >/dev/null
  fi
  echo "fetched $id"
done
echo "Now: godot --headless --path game --import && godot --headless --path game --script res://tools/bake_polyhaven.gd"
