# Aurora Forest: playable 3D graphics reference for Cgame

This directory is a **standalone playable reference project**, not a replacement for the user's existing game. It showcases engine capabilities using stock Godot resources plus the native `AdaptiveResolution3D` node introduced by [PR #907](https://github.com/demoh2019/Cgame/pull/907) and the fork's existing `WorldPartition3D` module.

## Features integrated into this demo

- **Streamed terrain:** every WorldPartition3D forest cell now creates its own 32 m × 32 m heightfield mesh and matching static `HeightMapShape3D` collider, with analytic vertex normals and vertex-colored PBR ground material. The old world-wide terrain mesh and trimesh collider have been removed.
- **Seam-preserving geometry LOD:** each patch has 33 × 33 vertices and automatic 2×/4×/8× coarse indexed LODs. Every outer 1 m border vertex remains represented at every LOD, preventing T-junction gaps when adjacent patches use different detail levels. High-detail surfaces use 2,048 triangles per patch; mathematical model LODs contain 1,088, 352, and 176 triangles respectively. Test these render thresholds on actual hardware.
- **WorldPartition3D streaming:** 16 registered 32 m × 32 m cells reference the **same** packed forest scene; the engine shares the threaded resource request, instantiates around the camera (one cell/frame) and unloads distant cells with hysteresis. The fork also exposes an `observer_cell_changed` event for region-aware gameplay; the demo displays the current cell without polling player coordinates.
- **Chunked GPU instancing:** each loaded cell generates up to 54 trees, 225 animated grass tufts, and 9 rocks using five or fewer MultiMesh draw groups, instead of one Node3D per instance. At most 3,600 grass tufts exist if all 16 cells are loaded.
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

The demo is deliberately small and asset-free. Its spheres, cylinders, quad blades and procedural sky are placeholders for real authored assets; it does **not** reimplement Unreal Nanite/Lumen. A full game should replace these with authored PBR meshes, materials, impostors/HLOD and authored PBR textures, asynchronous mesh generation/caching, a complete terrain authoring workflow and a larger-world asset/texture streaming solution. The effect budgets should be tuned with GPU measurements on actual target devices.

A `MultiMesh` is culled as one unit; therefore trees and grass are split into 16 **streamed local cell scenes** instead of one massive draw group. This sample **streams both terrain rendering and collision per cell**, but still keeps the eight collectible scene nodes persistent and creates procedural tile resources on the main thread. A production open world needs background tile generation, terrain caches/asset streaming, true HLOD/impostors, per-cell navigation meshes, collision warmup and origin management. Primitive colliders are re-created with each streamed cell; their counts should be profiled as world density increases. `WorldPartition3D` does not provide these automatically. The native `AdaptiveResolution3D` class is opt-in and should be used only once per viewport.

## Headless regression checks

With a **compiled Cgame binary** (the generic upstream editor lacks the fork's native nodes), from the repository root:

```sh
/path/to/cgame --headless --path misc/cgame_forest_showcase --script res://tests/smoke_streaming.gd
/path/to/cgame --headless --path misc/cgame_forest_showcase --script res://tests/smoke_saves.gd
/path/to/cgame --headless --path misc/cgame_forest_showcase --script res://tests/smoke_physics.gd
```

`smoke_streaming.gd` checks async shared-cell load/unload/reload, deterministic per-cell instance transforms, negative grid coordinates, streaming obstacle collision and performance density. `smoke_saves.gd` uses a separate throwaway save path, checking round-trip, deduplication, invalid JSON and version rejection. `smoke_physics.gd` instantiates the real scene, queries static terrain collision and checks that a spawned character falls onto the terrain; it also checks that obstacles are constructed in streamed cells. `smoke_streaming.gd` also checks seam heights/normals, heightmap dimensions and offset, and LOD index boundaries. **These GDScript smoke tests are added, not claimed to have been executed.**

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
- [ ] Verify capsule grounding, jumping, collision against trunks/rocks, world bounds, camera position and save/load after teleporting.
- [ ] Run all three added headless smoke scripts on the compiled fork.
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
- [Godot visibility ranges (HLOD)](https://docs.godotengine.org/en/stable/tutorials/3d/visibility_ranges.html)
- [Godot sky shaders](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/sky_shader.html)
