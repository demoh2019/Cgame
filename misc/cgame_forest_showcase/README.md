# Aurora Forest: playable 3D graphics reference for Cgame

This directory is a **standalone playable reference project**, not a replacement for the user's existing game. It showcases engine capabilities using stock Godot resources plus the native `AdaptiveResolution3D` node introduced by [PR #907](https://github.com/demoh2019/Cgame/pull/907) and the fork's existing `WorldPartition3D` module.

## Features integrated into this demo

- Deterministic rolling terrain with vertex normals derived from an analytic heightfield and vertex-colored PBR material.
- **WorldPartition3D streaming:** 16 registered 32 m × 32 m cells reference the **same** packed forest scene; the engine shares the threaded resource request, instantiates around the camera (one cell/frame) and unloads distant cells with hysteresis.
- **Chunked GPU instancing:** each loaded cell generates up to 54 trees, 225 animated grass tufts, and 9 rocks using five or fewer MultiMesh draw groups, instead of one Node3D per instance. At most 3,600 grass tufts exist if all 16 cells are loaded.
- Atmospheric procedural sky with the DirectionalLight3D sun, stable ambient sky radiance, cinematic AgX tone mapping, optional SSAO, SSIL, volumetric fog, and glowing collectible crystals.
- Exploration movement, mouse-look, eight collectible forest relics, HUD with loaded cell count, and interactive high/performance profiles.
- **Versioned local saves** under `user://` storing collected relics, camera and quality settings. `F5` saves, `F9` loads, collecting a relic automatically saves; invalid JSON or incompatible versions are rejected.
- Live 3D resolution scaling to a 60 FPS target using the fork's native GPU-time adaptation. When valid GPU timings are unavailable, the adaptive node deliberately does not change resolution.

## Run

1. Build Cgame from branch `feature/adaptive-resolution-gpu-budget` (or after PR #907 is merged). This is necessary for `AdaptiveResolution3D` and the built-in `world_partition` module (`WorldPartition3D`).
2. Open this **folder**, `misc/cgame_forest_showcase`, as a separate Godot project with that Cgame editor executable.
3. Use the Forward+ rendering backend and click Play. The project uses FSR2 and expects the selected rendering backend to support it.
4. Click inside the window to capture the mouse. **WASD / arrow keys** move, **mouse** looks around, **Shift** runs, **E** picks up nearby crystals, **F5/F9** save/load, **Esc** releases the mouse.
5. Press **F1** for the cinematic profile (SSAO, SSIL, volumetric fog and all grass), **F2** for the performance profile (less grass, no SSAO/SSIL/volumetric fog). GPU-budget scaling runs in both.

## Technical constraints

The demo is deliberately small and asset-free. Its spheres, cylinders, quad blades and procedural sky are placeholders for real authored assets; it does **not** reimplement Unreal Nanite/Lumen. A full game should replace these with authored PBR meshes, materials, impostors/HLOD and a complete tile-based terrain + texture streaming solution. The effect budgets should be tuned with GPU measurements on actual target devices.

A `MultiMesh` is culled as one unit; therefore trees and grass are split into 16 **streamed local cell scenes** instead of one massive draw group. This sample still retains a single terrain mesh, shared materials and all eight collectibles when distant; a production open world needs terrain and gameplay entity streaming, true HLOD/impostors, collision/navmesh warmup and origin management. `WorldPartition3D` does not provide these automatically. The native `AdaptiveResolution3D` class is opt-in and should be used only once per viewport.

## Headless regression checks

With a **compiled Cgame binary** (the generic upstream editor lacks the fork's native nodes), from the repository root:

```sh
/path/to/cgame --headless --path misc/cgame_forest_showcase --script res://tests/smoke_streaming.gd
/path/to/cgame --headless --path misc/cgame_forest_showcase --script res://tests/smoke_saves.gd
```

`smoke_streaming.gd` checks async shared-cell load/unload/reload, deterministic per-cell instance transforms, negative grid coordinates and performance density. `smoke_saves.gd` uses a separate throwaway save path, checking round-trip, deduplication, invalid JSON and version rejection. They are **added, not claimed to have been executed**.

## Verification checklist

- [ ] Engine compiles with the new native node, in both tools and template builds.
- [ ] Demo imports and scene starts with no errors on Cgame's Forward+ renderer.
- [ ] Sky shader compiles on Vulkan and Metal (note: `sky()` has no early `return`).
- [ ] Wind, grass instancing and sky render correctly on Apple M1.
- [ ] Walking through cell boundaries updates the loaded-cell HUD, preserves terrain/foliage alignment, and unloads/reloads cells without flicker.
- [ ] Run the two added headless smoke scripts on the compiled fork.
- [ ] Picking up eight crystals updates the HUD, the savegame persists after reopening, and profile switching changes measured GPU time.
- [ ] Confirm that GPU timings are available and adaptive resolution reacts to sustained load.
- [ ] Record frame time, GPU time, FPS, and VRAM in F1 and F2 profiles, using the same camera path.

These checks are not claimed complete until running the project on a compiled build.

## References

- [Unreal Engine dynamic resolution](https://dev.epicgames.com/documentation/en-us/unreal-engine/dynamic-resolution-in-unreal-engine)
- [Unity dynamic resolution control](https://docs.unity.cn/6000.0/Documentation/Manual/DynamicResolution-control.html)
- [Cgame WorldPartition3D module](../../modules/world_partition/README.md)
- [Unreal Engine World Partition / HLOD](https://dev.epicgames.com/documentation/en-us/unreal-engine/hierarchical-level-of-detail-in-unreal-engine)
- [Godot MultiMesh optimization](https://docs.godotengine.org/en/stable/tutorials/performance/using_multimesh.html)
- [Godot visibility ranges (HLOD)](https://docs.godotengine.org/en/stable/tutorials/3d/visibility_ranges.html)
- [Godot sky shaders](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/sky_shader.html)
