# Aurora Forest: playable 3D graphics reference for Cgame

This directory is a **standalone playable reference project**, not a replacement for the user's existing game. It showcases engine capabilities using stock Godot resources plus the native `AdaptiveResolution3D` node introduced by [PR #907](https://github.com/demoh2019/Cgame/pull/907) and the fork's existing `WorldPartition3D` module.

## Features integrated into this demo

- **Streamed terrain:** every WorldPartition3D forest cell now creates its own 32 m × 32 m heightfield mesh and matching static `HeightMapShape3D` collider, with analytic vertex normals and vertex-colored PBR ground material. The old world-wide terrain mesh and trimesh collider have been removed.
- **Bounded terrain cache:** a main-thread, 12-entry LRU keeps immutable ArrayMesh/HeightMapShape3D resources for recent cells. Revisiting a cached location reuses mesh and collider resources instead of rebuilding all 1,089 samples and LOD buffers. Live cache entries/hits/misses appear on the HUD. Active scene nodes are never stored in the cache; evicted resources remain alive only if used by an active cell.
- **Seam-preserving geometry LOD:** each patch has 33 × 33 vertices and automatic 2×/4×/8× coarse indexed LODs. Every outer 1 m border vertex remains represented at every LOD, preventing T-junction gaps when adjacent patches use different detail levels. High-detail surfaces use 2,048 triangles per patch; mathematical model LODs contain 1,088, 352, and 176 triangles respectively. Test these render thresholds on actual hardware.
- **CPU streamer telemetry:** the C++ WorldPartition3D node now measures the CPU duration of the most recent streaming update and its actual number of scene-instantiation attempts. Both appear on the HUD, alongside GPU frame time and loaded/pending cells. These samples are diagnostic and do not include later physics GPU work.
- **Bounded HLOD resource cache:** a second 96-entry LRU retains only immutable distant `ArrayMesh` and low-poly canopy `MultiMesh` resource pairs. Revisiting a recently departed horizon tile reconstructs just its small scene nodes while reusing GPU-ready meshes and instancing buffers. It never caches physics bodies or scene nodes. The HLOD HUD now reports cache occupancy, hits and misses separately from the 12-entry collision-terrain cache; the two capacities serve different workloads. LRU eviction does not destroy resources referenced by still-active render nodes.
- **Distant terrain HLOD:** a visual-only horizon layer creates compact mesh proxies outside the nearby authoritative WorldPartition3D cells and hides each proxy instantly when the detailed streamed terrain cell loads. The stitched 8× terrain LOD uses **153 vertices / 176 triangles** instead of the near tile's 1,089 vertices / 2,048 triangles, retaining all 128 boundary vertices at 1 m spacing for seam continuity. Distant canopies use a shared five-sided, two-ring low-poly SphereMesh with up to 54 instances per tile; the same deterministic tree RNG gives exactly matching full/distant crown transforms without loading any physics, trunks, grass or wind shader. Meshes use the same height function and shared PBR ground material, with a **separate distant-forest canopy MultiMesh** but **no physics colliders, trunks, grass, navigation or collectible entities**. The far forest batches up to 54 five-sided low-poly tree crowns per tile. Their deterministic transforms exactly match those of the nearby streamed WindCanopies and the source mesh/material are shared across all far tiles. Each tile holds only its own instance transforms; geometry, shader and physics costs stay lower than full trees. (The far canopies are not full billboard atlases or Nanite geometry.) Proxy creation is limited to two tiles per frame; HLOD radius is 6 cells in CINEMATIC and 4 in PERFORMANCE mode, and the HUD reports visible/prepared distant tiles plus visible canopy counts. This is not equivalent to Unreal's automatic HLOD mesh merging.
- **Predictive world streaming:** directional prefetch reads the player's physics velocity every 0.25 seconds and requests a 2-cell corridor in the direction of travel after servicing the normal observer radius. Prefetch changes do not force a teleport, bypass collision readiness, or use additional threads. The HUD shows the active X/Z direction, and the native streamer drops obsolete corridor tiles when turning.
- **WorldPartition3D streaming:** 1,024 registered 32 m × 32 m cells span a 1,024 m × 1,024 m world, all referencing the **same** PackedScene path. The engine shares the background resource request, prioritizes nearby cells, instantiates at most 2 cells per update (soft budget: 2 ms), and unloads distant cells with hysteresis. The fork also exposes an `observer_cell_changed` event for region-aware gameplay; the demo displays the current cell without polling player coordinates.
- **Shared forest resources:** tree trunks, wind-animated canopies, grass blades, rocks and terrain material now use a single immutable prototype per type, reused by all active and future cells. MultiMesh transforms and primitive colliders remain tile-specific. Headless streaming tests assert shared mesh identity across different tiles.
- **Chunked GPU instancing:** each loaded cell generates up to 54 trees, 225 animated grass tufts, and 9 rocks using five or fewer MultiMesh draw groups, instead of one Node3D per instance. The registered world contains up to 230,400 potential grass tufts, but only nearby cells create actual scene objects and GPU instances; scene lifetime remains bounded by streaming radii.
- Atmospheric procedural sky with the DirectionalLight3D sun, stable ambient sky radiance, cinematic AgX tone mapping, optional SSAO, SSIL, volumetric fog, and glowing collectible crystals.
- **First-person physics:** a capsule `CharacterBody3D` controller with frame-rate-independent gravity, grounded and air acceleration, sprinting, jumping, slope snapping and mouse look; collision from cell-local `HeightMapShape3D` physics resources plus dynamically streamed tree-trunk and boulder primitives. The explorer uses the C++ `WorldPartition3D.are_cells_loaded(cell, 0)` readiness query to freeze until the spawn/destination tile scene is instantiated. It probes both the forward capsule edge and its left/right flanks, preventing diagonal movement into unloaded neighboring tiles. Physics-server synchronization and visual shader readiness must still be validated in a running build.
- Exploration, eight collectible forest relics, HUD with loaded cell count, and interactive high/performance profiles.
- **Versioned local saves** under `user://` storing collected relics, camera and quality settings. `F5` saves, `F9` loads, collecting a relic automatically saves; invalid JSON or incompatible versions are rejected.
- Live 3D resolution scaling to a 60 FPS target using the fork's native GPU-time adaptation. When valid GPU timings are unavailable, the adaptive node deliberately does not change resolution.

## Run

1. Build Cgame from branch `feature/adaptive-resolution-gpu-budget` (or after PR #907 is merged). This is necessary for `AdaptiveResolution3D` and the built-in `world_partition` module (`WorldPartition3D`).
2. Open this **folder**, `misc/cgame_forest_showcase`, as a separate Godot project with that Cgame editor executable.
3. Use the Forward+ rendering backend and click Play. The project uses FSR2 and expects the selected rendering backend to support it.
4. Click inside the window to capture the mouse. **WASD / arrow keys** move, **mouse** looks around, **Shift** sprints, **Space** jumps, **E** picks up nearby crystals, **F5/F9** save/load, **Esc** releases the mouse.
5. Press **F1** for the cinematic profile (SSAO, SSIL, volumetric fog and all grass), **F2** for the performance profile (less grass, no SSAO/SSIL/volumetric fog). GPU-budget scaling runs in both.

## Technical constraints

The demo is a procedural, asset-free 1km-world prototype. Its spheres, cylinders, quad blades and procedural sky are placeholders for real authored assets; it does **not** reimplement Unreal Nanite/Lumen. A full game should replace these with authored PBR meshes/textures, high-quality impostors/HLOD, background asset preparation, a complete terrain authoring workflow, and persistent asset/texture streaming. The effect budgets should be tuned with GPU measurements on actual target devices.

A `MultiMesh` is culled as one unit; therefore trees and grass are split into spatially streamed local cell scenes rather than one massive draw group. This sample **streams both terrain rendering and collision per cell**, but still keeps the eight collectible scene nodes persistent and creates procedural tile resources on the main thread. A production open world needs background tile preparation and persistent disk caching (rather than only the 12-entry in-memory LRU), texture streaming, true HLOD/impostors, per-cell navigation meshes, collision warmup and origin management. Primitive colliders are re-created with each streamed cell; their counts should be profiled as world density increases. `WorldPartition3D` does not provide these automatically. The native `AdaptiveResolution3D` class is opt-in and should be used only once per viewport.

## Headless regression checks

With a **compiled Cgame binary** (the generic upstream editor lacks the fork's native nodes), from the repository root:

```sh
/path/to/cgame --headless --path misc/cgame_forest_showcase --script res://tests/smoke_streaming.gd
/path/to/cgame --headless --path misc/cgame_forest_showcase --script res://tests/smoke_saves.gd
/path/to/cgame --headless --path misc/cgame_forest_showcase --script res://tests/smoke_physics.gd
/path/to/cgame --headless --path misc/cgame_forest_showcase --script res://tests/smoke_terrain_cache.gd
/path/to/cgame --headless --path misc/cgame_forest_showcase --script res://tests/smoke_prefetch.gd
/path/to/cgame --headless --path misc/cgame_forest_showcase --script res://tests/smoke_distant_hlod.gd
/path/to/cgame --headless --path misc/cgame_forest_showcase --script res://tests/smoke_hlod_cache.gd
```

`smoke_streaming.gd` checks async shared-cell load/unload/reload, deterministic per-cell instance transforms, negative grid coordinates, streaming obstacle collision and performance density. `smoke_saves.gd` uses a separate throwaway save path, checking round-trip, deduplication, invalid JSON and version rejection. `smoke_physics.gd` instantiates the real scene, queries static terrain collision and checks that a spawned character falls onto the terrain; it also checks that obstacles are constructed in streamed cells. `smoke_streaming.gd` also checks seam heights/normals, heightmap dimensions and offset, LOD index boundaries, and shared cached mesh/heightfield object identity on reload. `smoke_terrain_cache.gd` verifies LRU behavior, resource identity, hit/miss statistics and 12-tile memory retention cap. `smoke_prefetch.gd` exercises forward cell priority, corridor extension, reversal, unload and disabled modes using the real native streamer. `smoke_distant_hlod.gd` checks compact terrain border vertices/heights/normals, low-poly canopy mesh/count, identical crown transforms against the real loaded forest, shared mesh identity with independent per-tile MultiMesh buffers, collision-free proxies, automatic handoff to full-detail terrain and the performance-profile radius. It also tests leaving the HLOD horizon and returning to the same cell to verify resource identity reuse and cache hits. `smoke_hlod_cache.gd` tests 96-entry LRU eviction, both resource identities, accounting, bounded memory retention and reset. `smoke_streaming.gd` also checks CPU time and instantiation attempt diagnostics stay within valid bounds. **These GDScript smoke tests are added, not claimed to have been executed.**

The independent mathematical terrain contract (`tests/test_terrain_streaming_contract.py`) can run without Godot and is included in the new `.github/workflows/cgame-forest-contracts.yml` CI job:

```sh
python3 -m unittest discover -s misc/cgame_forest_showcase/tests -p 'test_terrain_*.py' -v
```

## Verification checklist

- [ ] Engine compiles with the new native node, in both tools and template builds.
- [ ] Demo imports and scene starts with no errors on Cgame's Forward+ renderer.
- [ ] Sky shader compiles on Vulkan and Metal (note: `sky()` has no early `return`).
- [ ] Wind, grass instancing and sky render correctly on Apple M1.
- [ ] Walking through cell boundaries updates the loaded-cell HUD, preserves terrain/foliage alignment, and unloads/reloads cells without flicker.
- [ ] Check HeightMapShape3D collision at tile borders and on slopes, including mixed terrain LOD transitions.
- [ ] Confirm the character does not fall during initial tile streaming or during savegame teleport while destination physics loads.
- [ ] Inspect the three terrain LOD transition distances and measure GPU triangle savings on target hardware.
- [ ] Inspect far terrain and forest HLOD on Vulkan and Metal while traversing cell edges: look for Z-fighting, cracks, canopy popping, unexpected foliage brightness and main-thread tile generation spikes.
- [ ] Compare visible near and distant canopy transforms, colors and scene handoff on negative-coordinate tiles, save/load teleports, and F1/F2 toggling.
- [ ] Record WorldPartition3D streaming CPU update milliseconds, instantiation attempts, render GPU time and total frame time independently. Do not confuse the most recent CPU sample with full-frame time.
- [ ] Run and rapidly reverse player movement at streaming cell boundaries; verify predictive corridor priorities, stale-cell unload, safe collision handling and stable VRAM.
- [ ] Walk multiple kilometers of test routes and verify near-terrain cache entries never exceed 12 and HLOD resource cache entries never exceed 96; compare HLOD rebuild time on cold miss versus cache hit and check VRAM retention.
- [ ] Walk multiple kilometers of test routes and verify LRU cache entries never exceed 12, GPU memory remains bounded, revisit cache hits increase, and instantiation time budget limits repeated stalls.
- [ ] Verify capsule grounding, jumping, collision against trunks/rocks, world bounds, camera position and save/load after teleporting.
- [ ] Run all seven added headless smoke scripts on the compiled fork.
- [ ] Picking up eight crystals updates the HUD, the savegame persists after reopening, and profile switching changes measured GPU time.
- [ ] Confirm that GPU timings are available and adaptive resolution reacts to sustained load.
- [ ] Record frame time, GPU time, FPS, and VRAM in F1 and F2 profiles, using the same camera path.

These checks are not claimed complete until running the project on a compiled build.

## References

- [Unreal Engine dynamic resolution](https://dev.epicgames.com/documentation/en-us/unreal-engine/dynamic-resolution-in-unreal-engine)
- [Unity dynamic resolution control](https://docs.unity.cn/6000.0/Documentation/Manual/DynamicResolution-control.html)
- [Cgame WorldPartition3D module](../../modules/world_partition/README.md)
- [Unreal Engine World Partition / HLOD](https://dev.epicgames.com/documentation/en-us/unreal-engine/hierarchical-level-of-detail-in-unreal-engine)
- [Godot CharacterBody3D physics and floor snapping](https://docs.godotengine.org/en/stable/classes/class_characterbody3d.html)
- [Unreal Engine Character Movement Component](https://dev.epicgames.com/documentation/en-us/unreal-engine/movement-components-in-unreal-engine)
- [Godot heightfield collision shape](https://docs.godotengine.org/en/stable/classes/class_heightmapshape3d.html)
- [Godot procedural ArrayMesh LOD index arrays](https://docs.godotengine.org/en/stable/classes/class_arraymesh.html)
- [Unreal Engine World Partition](https://dev.epicgames.com/documentation/en-us/unreal-engine/world-partition-in-unreal-engine)
- [Godot MultiMesh optimization](https://docs.godotengine.org/en/stable/tutorials/performance/using_multimesh.html)
- [Unreal World Partition HLOD and foliage instancing](https://dev.epicgames.com/documentation/unreal-engine/world-partition---hierarchical-level-of-detail-in-unreal-engine)
- [Godot visibility ranges (HLOD)](https://docs.godotengine.org/en/stable/tutorials/3d/visibility_ranges.html)
- [Godot sky shaders](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/sky_shader.html)
