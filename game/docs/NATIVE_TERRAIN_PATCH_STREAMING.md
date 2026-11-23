# Cgame P1 — Sparse editable terrain patches

**Scope:** native engine + canonical `game/` project. This is an incremental step toward a large-world terrain authoring pipeline, not a claim that Terrain3D, World Partition or GPU-driven virtualized geometry are feature-complete.

## What changed

The existing `ChunkedTerrain3D` scene node already supports bounded terrain chunks, skirted mesh LOD, a shared CPU mesh-build budget, camera-priority streaming, near-viewer heightmap collision and optional vertex-color material data. The preceding P1 patch added atomic sparse height updates. This increment builds on it with cheaper vertex-color changes and live non-destructive 3D editor sculpting.

New native APIs:

- `apply_height_patch(region: Rect2i, heights: PackedFloat32Array) -> bool` (already present in develop): edits in-bounds row-major samples in-place and invalidates only affected and adjacent chunk mesh caches. Recomputes bounds, geometric error per LOD, nearby physics shapes, and schedules the normal chunk streaming update.
- `apply_color_patch(region: Rect2i, colors: PackedColorArray) -> bool`: edits initialized vertex colors without changing height, geometry error, or collision. Only the render mesh is invalidated.
- `get_last_region_invalidated_chunks() -> int`: tracks invalidated render chunks for tests and diagnostics. Identical-value edits invalidate zero.
- Strict pre-validation prevents partial writes from invalid coordinates, incomplete data or nonfinite heights/colors.

Patch coordinates are **sample indices**, not world coordinates; rectangular arrays use x-major rows. An edit at a shared edge also invalidates neighboring chunks. Source meshes outside the dirty area keep their cached LOD geometry and physics RIDs. `force_update()` refreshes dirty render/physics shapes immediately; normal frame updates retain the existing mesh time budget.

When `set_normal_data()` has installed a custom normal grid, the native engine recomputes its modified normal neighborhood. The bridge submits a one-sample halo for consistent boundaries. Do not use these methods to modify authoritative online world physics from a client.

## In the actual game

- `game/scripts/client/terrain_edit_bridge.gd` bridges `TerrainEditLayers` to the native two-argument height patch method by processing dirty authoring chunks and adding a one-sample halo; the engine recomputes custom normals.
- `game/addons/cgame_terrain_tools/plugin.gd` now binds the selected `ChunkedTerrain3D` in the scene to the existing terrain dock; brush strokes, layer visibility/opacity/order and Undo/Redo update the selected real node rather than just an isolated preview. To sculpt directly in the 3D viewport, select the node, enable **Sculpt selected terrain (3D viewport)** in the dock, then left-click the ground. Disable the toggle to restore normal object picking; modifier-clicks continue to navigate the editor. This increment supports discrete click strokes, not continuous dragged strokes.
- `game/scripts/client/chunk_view.gd` uses `apply_color_patch()` to update the canonical Albion After terrain's cached curvature/sky-visibility vertex colors when lighting quality changes, falling back to `set_color_data()` on older binaries.
- The existing game collision policy is intentionally preserved: online clients render their terrain without local terrain collision; the **server** remains authoritative for survivability, navigation and movement. Editor terrain nodes with collision enabled get localized physics updates.

Example direct native edit:

```gdscript
var region := Rect2i(10, 10, 2, 2)
var heights := PackedFloat32Array([0.45, 0.52, 0.48, 0.50])
assert($ChunkedTerrain3D.apply_height_patch(region, heights))
$ChunkedTerrain3D.force_update()
```

For a custom-normal grid, use the engine's two-argument height patch API; neighboring normals are recalculated automatically.

## Tests

- `tests/scene/test_chunked_terrain_3d.cpp`: existing native height-patch/LOD/collision regressions, plus new color-only patch tests that preserve active collision and reject malformed paint.
- `game/tests/test_terrain_edit_bridge.gd`: authoring layers + native patches, undo, custom-normal support, editor dock's live bind/stroke/undo path, graphics color-patch integration, and dimension mismatch safety. Registered in `run_all.gd`.

With a compiled editor / Cgame test binary:

```sh
bin/godot.macos.editor.arm64 --headless --test --test-case="*[ChunkedTerrain3D]*"
bin/godot.macos.editor.arm64 --headless --path game --script res://tests/run_one.gd -- test_terrain_edit_bridge test_terrain_mesh_streaming
```

## Remaining gaps

This does **not** add GPU meshlet rendering, virtual geometry page streaming, terrain texture arrays with GPU splat-page feedback, World Partition HLOD baking, or a unified GPU GI/shadow pipeline. The original small `HeightmapTerrain3D` prototype remains separate; the large-world path is `ChunkedTerrain3D` plus non-destructive game-side `TerrainEditLayers`. GPU correctness and throughput measurements still require hardware checks and a matching compiled engine.
