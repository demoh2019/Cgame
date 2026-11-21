# Batch camera screen-space LOD for streamed Albion After grass

## Engine feature and Unreal comparison

Unreal Engine's static-mesh LOD framework uses projected screen size when
choosing the complexity of a visual mesh. The Cgame fork already exposed
`Camera3D.get_pixels_per_meter_at_position(world_point)`, but code that
updates many instanced tiles had to call the method once per tile.

Cgame adds `Camera3D.get_pixels_per_meter_at_positions(world_points)`:

```gdscript
var positions := PackedVector3Array([
    Vector3(0, 0, -10), Vector3(0, 0, -20)])
var pixels_per_meter: PackedFloat64Array = camera.call(
    "get_pixels_per_meter_at_positions", positions)
```

The engine now computes **one viewport projection** and **one inverse adjusted
camera transform** for an entire group of up to 4096 points. Each result
matches the prior scalar method including perspective, orthographic and
asymmetric frustum projection, keep-aspect rules and camera orientation.
Behind-camera perspective points get 0 pixels/m. Invalid or nonfinite
positions and oversized batches reject the complete request (empty array)
before partial results can affect LOD selection.

The result is in **logical viewport pixels**. The game still multiplies by
`scaling_3d_scale` on supported 3D renderers. No GPU readback, physics,
world streaming state or mesh buffer mutation occurs inside the native API.
This is batched screen coverage, **not Nanite** or automatic mesh baking.

Unreal references:
- https://dev.epicgames.com/documentation/en-us/unreal-engine/optimizing-lod-screen-size-per-platform-in-unreal-engine
- https://dev.epicgames.com/documentation/en-us/unreal-engine/static-mesh-automatic-lod-generation-in-unreal-engine

## Production game integration

In `game/scripts/client/chunk_view.gd`, `_update_grass_lods()` already
selects real grass MultiMesh meshes (18/9/4 blades) and visible instance
counts for each streamed tile. It skips all work for a stationary camera.
Once the 0.35-second refresh interval is reached and the camera changed,
the game now:

1. Packs current tile centers into one `PackedVector3Array`.
2. Calls the native batched Camera3D method once, only if supported and if
   there are 4096 or fewer tiles.
3. Uses the returned density for exactly the same existing
   `GrassField.projected_lod_distance`, hysteresis and geometry budget.
4. If the native method is absent or rejects the group, uses the existing
   per-tile scalar call. On stock Godot it keeps the original FOV-based
   screen LOD approximation.

No new tile nodes, mesh reuploads, frame-rate dependencies, gameplay
collisions, client/server interactions or changes to authored LOD
thresholds are required. The optimization reduces repeated **camera matrix
setup and script-to-C++ calls**; whether it improves frame time depends on
the number of visible grass tiles and must be benchmarked in a running game.

## Verification

- Engine doctests in `tests/scene/test_camera_3d.cpp` cover scalar parity
  across perspective, KEEP_WIDTH, rotated isometric, orthographic and frustum
  cameras, plus zero/behind-camera inputs and 4096/4097 boundaries.
- Live game integration tests in `game/tests/test_camera_pixel_density.gd`
  verify the real streamed-grass dispatch/fallback and per-tile scalar parity.
- Source contract: `tests/scene/test_camera_bulk_screen_lod_contract.py`.
- Native/Godot CI: `.github/workflows/native-camera-bulk-screen-lod.yml`.
