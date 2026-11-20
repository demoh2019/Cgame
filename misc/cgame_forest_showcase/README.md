# Aurora Forest: playable 3D graphics reference for Cgame

This directory is a **standalone playable reference project**, not a replacement for the user's existing game. It showcases engine capabilities using stock Godot resources plus the native `AdaptiveResolution3D` node introduced by [PR #907](https://github.com/demoh2019/Cgame/pull/907) and the fork's existing `WorldPartition3D` module.

## Features integrated into this demo

- Deterministic rolling terrain with vertex normals derived from an analytic heightfield and vertex-colored PBR material.
- **Predictive scene streaming:** Aurora Forest feeds the first-person character's velocity into the native streamer. A bounded 2.5-second / 28-meter lookahead requests one upcoming cell before crossing its border, after visible and pinned cells. The HUD shows the target and **F3** toggles this feature for A/B comparison.
- **Persistent home clearing:** native `pin_cell(Vector2i.ZERO)` retains a home hub even outside the unload radius, with a low-cost emissive beacon, a shadow-free OmniLight and a pinned-cell HUD counter. Removing a pin returns the cell to ordinary unload behavior (verified by the streaming smoke test).
- **WorldPartition3D streaming:** 16 registered 32 m × 32 m cells reference the **same** packed forest scene; the engine shares the threaded resource request, instantiates around the camera (one cell/frame) and unloads distant cells with hysteresis. The fork also exposes an `observer_cell_changed` event for region-aware gameplay; the demo displays the current cell without polling player coordinates.
- **Chunked GPU instancing:** each loaded cell generates up to 54 trees, 225 animated grass tufts, and 9 rocks using five or fewer MultiMesh draw groups, instead of one Node3D per instance. At most 3,600 grass tufts exist if all 16 cells are loaded.
- Atmospheric procedural sky with the DirectionalLight3D sun, stable ambient sky radiance, cinematic AgX tone mapping, optional SSAO, SSIL, volumetric fog, and glowing collectible crystals.
- **First-person physics:** a capsule `CharacterBody3D` controller with frame-rate-independent gravity, grounded and air acceleration, sprinting, jumping, slope snapping and mouse look; collision from the terrain's generated triangle mesh plus dynamically streamed tree-trunk and boulder primitives.
- Exploration, eight collectible forest relics, HUD with loaded cell count, and interactive high/performance profiles.
- **Versioned local saves** under `user://` storing collected relics, camera and quality settings. `F5` saves, `F9` loads, collecting a relic automatically saves; invalid JSON or incompatible versions are rejected.
- Live 3D resolution scaling to a 60 FPS target using the fork's native GPU-time adaptation. When valid GPU timings are unavailable, the adaptive node deliberately does not change resolution.

## Run

1. Build Cgame from branch `feature/adaptive-resolution-gpu-budget` (or after PR #907 is merged). This is necessary for `AdaptiveResolution3D` and the built-in `world_partition` module (`WorldPartition3D`).
2. Open this **folder**, `misc/cgame_forest_showcase`, as a separate Godot project with that Cgame editor executable.
3. Use the Forward+ rendering backend and click Play. The project uses FSR2 and expects the selected rendering backend to support it.
4. Click inside the window to capture the mouse. **WASD / arrow keys** move, **mouse** looks around, **Shift** sprints, **Space** jumps, **E** picks up nearby crystals, **F5/F9** save/load, **Esc** releases the mouse.
5. Press **F3** to enable/disable velocity-driven prefetch. In the HUD, an upcoming coordinate means a distinct next cell; `—` means no distinct forecast, and `OFF` means the feature is disabled.
6. Press **F1** for the cinematic profile (SSAO, SSIL, volumetric fog and all grass), **F2** for the performance profile (less grass, no SSAO/SSIL/volumetric fog). GPU-budget scaling runs in both.

## Technical constraints

The demo is deliberately small and asset-free. Its spheres, cylinders, quad blades and procedural sky are placeholders for real authored assets; it does **not** reimplement Unreal Nanite/Lumen. A full game should replace these with authored PBR meshes, materials, impostors/HLOD and a complete tile-based terrain + texture streaming solution. The effect budgets should be tuned with GPU measurements on actual target devices.

A `MultiMesh` is culled as one unit; therefore trees and grass are split into 16 **streamed local cell scenes** instead of one massive draw group. This sample still retains a single terrain/collision mesh, shared materials and all eight collectibles when distant; a production open world needs terrain and gameplay entity streaming, true HLOD/impostors, collision/navmesh warmup and origin management. Primitive colliders are re-created with each streamed cell; their counts should be profiled as world density increases. `WorldPartition3D` does not provide these automatically. The native `AdaptiveResolution3D` class is opt-in and should be used only once per viewport.

## Headless regression checks

With a **compiled Cgame binary** (the generic upstream editor lacks the fork's native nodes), from the repository root:

```sh
/path/to/cgame --headless --path misc/cgame_forest_showcase --script res://tests/smoke_streaming.gd
/path/to/cgame --headless --path misc/cgame_forest_showcase --script res://tests/smoke_saves.gd
/path/to/cgame --headless --path misc/cgame_forest_showcase --script res://tests/smoke_physics.gd
```

`smoke_streaming.gd` checks motion prefetch before the observer crosses a cell boundary, persistent home-cell pinning and unpinning, async shared-cell load/unload/reload, deterministic per-cell instance transforms, negative grid coordinates, streaming obstacle collision and performance density. `smoke_saves.gd` uses a separate throwaway save path, checking round-trip, deduplication, invalid JSON and version rejection. `smoke_physics.gd` instantiates the real scene, queries static terrain collision and checks that a spawned character falls onto the terrain; it also checks that obstacles are constructed in streamed cells. These tests are **added, not claimed to have been executed**.

## Verification checklist

- [ ] Engine compiles with the new native node, in both tools and template builds.
- [ ] Demo imports and scene starts with no errors on Cgame's Forward+ renderer.
- [ ] Sky shader compiles on Vulkan and Metal (note: `sky()` has no early `return`).
- [ ] Wind, grass instancing and sky render correctly on Apple M1.
- [ ] Confirm F3 toggles prediction and run a repeated sprint path while comparing scene load delay, FPS and memory usage in both modes.
- [ ] The (0,0) home beacon remains loaded beyond the unload radius; unpinning it allows unloading, and pinning cannot exceed 128 cells.
- [ ] Walking through cell boundaries updates the loaded-cell HUD, preserves terrain/foliage alignment, and unloads/reloads cells without flicker.
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
- [Godot MultiMesh optimization](https://docs.godotengine.org/en/stable/tutorials/performance/using_multimesh.html)
- [Godot visibility ranges (HLOD)](https://docs.godotengine.org/en/stable/tutorials/3d/visibility_ranges.html)
- [Godot sky shaders](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/sky_shader.html)
