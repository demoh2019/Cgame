# P1: Partial Landscape terrain edits — Cgame engine and Albion After

## Why this work is part of the Unreal-style Landscape effort

Unreal Engine Landscape uses separate components for rendering, visibility
and collision. For Cgame's large worlds, the corresponding renderer is the
**existing** `ChunkedTerrain3D` in `scene/3d/`, *not* the unrelated small
`HeightmapTerrain3D` editor prototype. The game already uses this native
`ChunkedTerrain3D` for each outdoor world-streaming chunk, with geometric
screen-size LOD, lazy mesh build budgets, materials and quality scaling.

Reference: https://dev.epicgames.com/documentation/unreal-engine/landscape-technical-guide-in-unreal-engine

## New engine API

```gdscript
var terrain: ChunkedTerrain3D = $ChunkedTerrain3D
# Example: update a 2 x 2 region in source sample coordinates:
var ok: bool = terrain.apply_height_patch(
    Rect2i(14, 22, 2, 2),
    PackedFloat32Array([0.40, 0.45, 0.42, 0.46]))
if ok:
    terrain.force_update() # Optional synchronous update; use normal cadence otherwise.
```

`apply_height_patch(region, heights)` atomically validates and replaces a
rectangular height region (up to **4096** samples per call) in existing native
height data. It leaves every other source sample intact, and does **not**
call `set_height_data` or rebuild the entire world.

- On invalid dimension, out-of-bounds coordinates, malformed length, NaN/Inf
  or image-backed terrain without source height array, nothing is changed.
- A byte-identical patch performs no mesh or collision invalidation.
- A changed patch invalidates only overlapping existing chunk mesh RIDs and
  nearby physics heightmap shapes; neighboring chunks are included where
  one-sample normal derivatives would otherwise be stale.
- Externally supplied normals in the edited one-sample ring are updated
  coherently. Other custom normals and vertex colors remain.
- Each edited chunk recomputes **LOD geometric error at all eight supported
  levels**, including bounds. Previously `update_region()` left the error
  cache stale, so newly raised hills could incorrectly receive low detail.
- Physics colliders are created again by the normal chunk update if enabled;
  `force_update()` applies changes immediately in the editor/tests, while
  ordinary game use honors its existing update and mesh-build cadence.
- `get_chunk_lod_error(chunk, lod)` exposes the native cached error for
  profiling and tests; no new per-frame CPU work or GPU buffers are needed
  outside a requested edit.

### Real Albion After debug validation

The online game already tags its streamed outdoor terrain nodes with
`aa_chunked_terrain_lod`. On a **debug build**, press **Ctrl+Shift+F9**.
The game finds the existing native tile under the player and sculpts a
small (2 m radius, +0.75 m) local visual patch into it using the new engine
API. The change is immediately rendered; no separate preview mesh is added.

This intentionally remains a **cosmetic development tool**. Albion's client
has `collision_enabled = false` on that terrain and the server continues to
own real movement, physics and ground height. It must not be exposed as
persisted multiplayer terraforming without authoritative server validation,
save/restore, erosion and collision/navigation updates. An old engine or
stock Godot simply reports the API unavailable and the normal F9 action
still works.

### Honest limitations

This P1 step is **not** a finished Unreal Landscape replacement:
it does not implement tiled disk asset serialization, cross-node terrain
edit persistence, HLOD baking, async physics cooking, live navigation rebake,
or a GPU virtualized heightfield renderer. In-editor sculpt brushes on the
smaller `HeightmapTerrain3D` have their own separate toolchain.

The code and tests do *not* establish a GPU performance improvement; the
expected benefit is avoiding full mesh/collision rebuilds for localized
edits, with correct dirty-chunk LOD state.

### Validation

- `tests/scene/test_chunked_terrain_3d.cpp`: focused native doctests for
  dirty-chunk LOD error, unchanged distant chunks, restored shape, normal
  regeneration, 4096-bound and invalid late samples.
- `game/tests/test_terrain_live_patch.gd`: actual production
  `ChunkedTerrain3D` with the live game patch wrapper and headless
  streamed-group dispatch.
- `tests/scene/test_terrain_partial_patch_contract.py`: source guards.
- `.github/workflows/native-terrain-partial-patches.yml`: compile, native
  tests and headless Albion tests.

## Next P1 gates

1. **Nanite-style virtual geometry:** implement a GPU-resident cluster
   visibility/draw path, cluster page caching and eviction, complete vertex
   attribute preservation, hardware GPU/driver benchmark matrix.
2. **Lumen-style unified GI:** bind real light/geometry visibility, diffuse
   and specular tracing, temporal denoising, BVH or distance-field fallback,
   GPU capture correctness and frame-time budgets.
3. **Virtual Texturing and VSM:** validate actual feedback from the renderer,
   GPU page residency, material sampling and shadow atlas update barriers.
4. **Landscape completion:** tile persistence and streaming source
   integration, collision-safe authoritative edits, navmesh invalidation,
   HLOD generation and large-map editor workflows.

Each is a separate substantive integration and hardware-validation stage;
none should be marked complete from CPU policy unit tests alone.
