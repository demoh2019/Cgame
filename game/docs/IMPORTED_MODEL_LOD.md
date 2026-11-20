# Imported model LOD pipeline — Albion After

## Why this change

Godot 4 automatically generates mesh levels of detail when importing 3D scenes
(including glTF). Our game's model catalog bakes models into world units and
re-centers meshes to populate a large environment with MultiMesh instances.
Before this change, calls to `ArrayMesh.add_surface_from_arrays()` copied only
the full-resolution triangles; they discarded the importer-generated LOD index
buffers. The wind material conversion for vegetation did the same.

Godot reference:
- https://docs.godotengine.org/en/stable/tutorials/3d/mesh_lod.html
- https://docs.godotengine.org/en/stable/classes/class_renderingserver.html
- https://docs.godotengine.org/en/stable/classes/class_viewport.html

The same general principle — reduce geometric complexity with increasing
viewing distance — is used in Unreal Engine's HLOD workflow and Unity's
LODGroup. We do **not** claim to reproduce Nanite or GPU-driven meshlets.

## What changed

- `scripts/client/mesh_lod_preservation.gd` reconstructs the imported LOD
  index dictionaries from `RenderingServer.mesh_get_surface()`. It supports
  both 16-bit and 32-bit index buffers. It reads the source mesh **once per
  cached model build**, not each frame.
- `model_catalog.gd` retains imported LOD levels for re-centered props,
  scaled/rotated buildings, rocks, and detailed scenery. LOD thresholds use
  the same world scale as the baked vertices; source vertex indices remain
  unchanged.
- `foliage.gd` retains LOD levels when rebuilding materials for wind.
- `graphics_quality.gd` sets viewport-native `mesh_lod_threshold` in every
  preset. Higher quality means sharper geometry longer:

| Preset | LOD threshold, pixels |
| --- | ---: |
| Performance | 2.6 |
| Balanced | 1.5 |
| High | 1.0 (Godot default) |
| Ultra | 0.65 |

Godot automatically selects the available LOD based on camera projection.
Meshes too small for importer-generated LODs continue drawing normally. There
is no extra mesh generation at runtime and no authoritative game logic change.

## Verification

Run the Godot import step and tests from the repository root:

```sh
godot --headless --editor --path game --quit
godot --headless --path game --script res://tests/run_all.gd
```

The new `test_imported_mesh_lod.gd` uses a synthetic indexed mesh with a
simplified LOD and checks index retention through fit and wind paths, scale
thresholds, and monotonic graphics presets. This checks the plumbing but
**does not measure FPS**. Benchmark before/after in the same streamed forest
and city route across Performance/High/Ultra: p50/p95 frame time, vertex
count, draw calls, texture memory and LOD transition stability. Test both
Compatibility and Forward+ where supported. No local Godot executable was
available in the editing environment for an actual runtime test.

## Limits

Do not copy source shadow mesh RIDs after vertex transforms: their positions
would differ. The output resources keep the existing material logic. Meshes
with no LOD data have an empty LOD dictionary and render the original
triangles. For mesh surgery that changes vertex indices (e.g. splitting a
source mesh into disconnected islands), do not reuse the original LOD indices.
