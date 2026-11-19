#!/bin/bash
# Fetches Zylann's Godot Voxel (MIT) so it can be built into this fork as an out-of-tree module:
#   misc/third_party/fetch_voxel_module.sh                      # clones into out/custom_modules/voxel
#   scons platform=macos arch=arm64 target=editor custom_modules=out/custom_modules
# It is opt-in on purpose: it adds about 6 minutes to a full build and every default build and CI job is
# unaffected. Verified on this fork (macOS arm64): the module compiles without changes and VoxelTerrain,
# VoxelBuffer, VoxelMesherBlocky, VoxelGeneratorFlat and VoxelStreamMemory are registered.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DEST="${1:-$ROOT/out/custom_modules}"
mkdir -p "$DEST"
if [ -d "$DEST/voxel/.git" ]; then
  git -C "$DEST/voxel" pull --ff-only
else
  git clone --depth 1 https://github.com/Zylann/godot_voxel.git "$DEST/voxel"
fi
echo "Voxel module ready: build with custom_modules=$DEST"
