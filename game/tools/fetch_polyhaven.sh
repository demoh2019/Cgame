#!/bin/bash
# Downloads the Poly Haven (CC0) sources of the baked models and terrain textures again, for re-baking with
# tools/bake_polyhaven.gd. The repository keeps only the baked meshes and the shrunk textures.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
MODELS="stone_fire_pit wooden_lantern_01 boulder_01 dead_tree_trunk_02 tree_stump_01 rock_moss_set_01 rock_moss_set_02 wooden_crate_01 horse_statue_01 wooden_bucket_01 namaqualand_boulder_02 wine_barrel_01 wooden_barrels_01"
for id in $MODELS; do
  mkdir -p "$HERE/assets/models/polyhaven/$id"
  curl -s "https://api.polyhaven.com/files/$id" | python3 -c '
import json, sys, os, urllib.request
id, folder = sys.argv[1], sys.argv[2]
g = json.load(sys.stdin)["gltf"]["1k"]["gltf"]
urllib.request.urlretrieve(g["url"], os.path.join(folder, id + ".gltf"))
for rel, info in g.get("include", {}).items():
    path = os.path.join(folder, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if not os.path.exists(path):
        urllib.request.urlretrieve(info["url"], path)
' "$id" "$HERE/assets/models/polyhaven/$id"
  echo "fetched $id"
done
echo "Now: godot --headless --path game --import && godot --headless --path game --script res://tools/bake_polyhaven.gd"
