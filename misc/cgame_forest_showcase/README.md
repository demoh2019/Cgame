# Aurora Forest: playable 3D graphics reference for Cgame

This directory is a **standalone playable reference project**, not a replacement for the user's existing game. It showcases engine capabilities using stock Godot resources plus the native `AdaptiveResolution3D` node introduced by [PR #907](https://github.com/demoh2019/Cgame/pull/907) and the fork's existing `WorldPartition3D` module.

## Features integrated into this demo

- Deterministic rolling terrain with vertex normals derived from an analytic heightfield and vertex-colored PBR material.
- **Playable streamed combat encounters:** deterministic per-cell forest stalkers use capsule CharacterBody3D physics, chase/leash behavior, close-range attacks with cooldown, three-hit HP, and a visible emissive-eye material. The encounter director limits the world to **5 spawned NPCs**, scans loaded near-detail cells only every 0.35 s, enables physics only within 24 m and removes enemies when cells unload. The player has 100 HP, short hit invulnerability, and respawns safely at the camp on defeat. **F / left-click while mouse is captured** swings at physics-visible opponents (blocked by trees/terrain). Each defeated encounter is saved and never respawns after streaming reload.
- **Relic quest navigation + remote cell preloading:** the game chooses the nearest remaining relic, remembers it until collection, shows a luminous waypoint and player-relative compass/distance in the HUD, and keeps its remote forest cell prepared through a named native source. Collecting a relic selects the next target; finishing all eight removes the extra loading source. Progress remains derived from existing saved relic IDs.
- **Seam-resistant LOD:** native `detail_hysteresis_cells = 1` means an already-full-detail forest cell stays full for an extra ring before demotion; the original inner radius remains the promotion threshold. This reduces rapid foliage/collider reconstruction when the player moves back and forth near boundaries.
- **Distance LOD forest:** with a 2-cell streaming radius, the inner 1-cell radius uses 54 trees, 225 grass tufts, 9 rocks and local obstacle colliders per cell, while outer cells use 16 deterministic tree silhouettes with cheaper foliage meshes and no per-tree physics or shadows. Pinned home hubs stay full-detail even when far away. **F4** toggles the native detail system and the HUD counts distant cells.
- **Predictive scene streaming:** Aurora Forest feeds the first-person character's velocity into the native streamer. A bounded 2.5-second / 28-meter lookahead requests one upcoming cell before crossing its border, after visible and pinned cells. The HUD shows the target and **F3** toggles this feature for A/B comparison.
- **Persistent home clearing:** native `pin_cell(Vector2i.ZERO)` retains a home hub even outside the unload radius, with a low-cost emissive beacon, a shadow-free OmniLight and a pinned-cell HUD counter. Removing a pin returns the cell to ordinary unload behavior (verified by the streaming smoke test).
- **WorldPartition3D streaming:** 16 registered 32 m × 32 m cells reference the **same** packed forest scene; the engine shares the threaded resource request, instantiates around the camera (one cell/frame) and unloads distant cells with hysteresis. The fork also exposes an `observer_cell_changed` event for region-aware gameplay; the demo displays the current cell without polling player coordinates.
- **Chunked GPU instancing:** each loaded cell generates up to 54 trees, 225 animated grass tufts, and 9 rocks using five or fewer MultiMesh draw groups, instead of one Node3D per instance. At most 3,600 grass tufts exist if all 16 cells are loaded.
- **Day/night and weather:** a 16-minute 24-hour clock drives directional sunlight, AgX sky colors, ambient energy, fog and cloud coverage twice per second. Clear, overcast and mist presets; nighttime procedural north-facing aurora ribbons are rendered without a `TIME`-dependent sky shader. F6 cycles weather, F7 pauses time and F8 jumps 3 in-game hours. Time and weather are saved in backward-compatible v1 save files.
- Atmospheric procedural sky with the DirectionalLight3D sun, stable ambient sky radiance, cinematic AgX tone mapping, optional SSAO, SSIL, volumetric fog, and glowing collectible crystals.
- **First-person physics:** a capsule `CharacterBody3D` controller with frame-rate-independent gravity, grounded and air acceleration, sprinting, jumping, slope snapping and mouse look; collision from the terrain's generated triangle mesh plus dynamically streamed tree-trunk and boulder primitives.
- Exploration, eight collectible forest relics, HUD with loaded cell count, and interactive high/performance profiles.
- **Versioned local saves** under `user://` storing collected relics, camera and quality settings. `F5` saves, `F9` loads, collecting a relic automatically saves; invalid JSON or incompatible versions are rejected.
- Live 3D resolution scaling to a 60 FPS target using the fork's native GPU-time adaptation. When valid GPU timings are unavailable, the adaptive node deliberately does not change resolution.

## Run

1. Build Cgame from branch `feature/adaptive-resolution-gpu-budget` (or after PR #907 is merged). This is necessary for `AdaptiveResolution3D` and the built-in `world_partition` module (`WorldPartition3D`).
2. Open this **folder**, `misc/cgame_forest_showcase`, as a separate Godot project with that Cgame editor executable.
3. Use the Forward+ rendering backend and click Play. The project uses FSR2 and expects the selected rendering backend to support it.
4. Approach forest stalkers, aim at their glowing eyes and press **F** (or left-click while mouse is captured) to strike. Three hits defeat a stalker. Enemy attacks reduce HP, while defeat returns you to the safe home clearing without clearing relics or defeated-enemy progression.
5. Follow the glowing blue objective beacon and the direction/distance indicator in the HUD. Collect with E to retarget the next relic. A dedicated streaming source prepares the quest cell remotely.
6. Click inside the window to capture the mouse. **WASD / arrow keys** move, **mouse** looks around, **Shift** sprints, **Space** jumps, **E** picks up nearby crystals, **F5/F9** save/load, **Esc** releases the mouse.
7. Press **F6** to cycle clear/cloudy/mist, **F7** to pause/resume the day/night clock and **F8** to jump ahead 3 in-game hours. Changes are shown in the HUD and persist across save/load (F5/F9).
8. Press **F4** to enable/disable near/far cell detail and compare GPU cost, CPU physics and memory use. When disabled, all loaded cells return to full detail under the 2-transitions/frame budget.
9. Press **F3** to enable/disable velocity-driven prefetch. In the HUD, an upcoming coordinate means a distinct next cell; `—` means no distinct forecast, and `OFF` means the feature is disabled.
10. Press **F1** for the cinematic profile (SSAO, SSIL, volumetric fog and all grass), **F2** for the performance profile (less grass, no SSAO/SSIL/volumetric fog). GPU-budget scaling runs in both.

## Technical constraints

The demo is deliberately small and asset-free. Its spheres, cylinders, quad blades and procedural sky are placeholders for real authored assets; it does **not** reimplement Unreal Nanite/Lumen. A full game should replace these with authored PBR meshes, materials, impostors/HLOD and a complete tile-based terrain + texture streaming solution. The effect budgets should be tuned with GPU measurements on actual target devices.

A `MultiMesh` is culled as one unit; therefore trees and grass are split into 16 **streamed local cell scenes** instead of one massive draw group. This sample still retains a single terrain/collision mesh, shared materials and all eight collectibles when distant; a production open world needs terrain and gameplay entity streaming, true HLOD/impostors, collision/navmesh warmup and origin management. Primitive colliders are re-created with each streamed cell; their counts should be profiled as world density increases. `WorldPartition3D` does not provide these automatically. The native `AdaptiveResolution3D` class is opt-in and should be used only once per viewport.

## Headless regression checks

With a **compiled Cgame binary** (the generic upstream editor lacks the fork's native nodes), from the repository root:

```sh
/path/to/cgame --headless --path misc/cgame_forest_showcase --script res://tests/smoke_streaming.gd
/path/to/cgame --headless --path misc/cgame_forest_showcase --script res://tests/smoke_saves.gd
/path/to/cgame --headless --path misc/cgame_forest_showcase --script res://tests/smoke_physics.gd
/path/to/cgame --headless --path misc/cgame_forest_showcase --script res://tests/smoke_lod.gd
/path/to/cgame --headless --path misc/cgame_forest_showcase --script res://tests/smoke_atmosphere.gd
/path/to/cgame --headless --path misc/cgame_forest_showcase --script res://tests/smoke_sources.gd
/path/to/cgame --headless --path misc/cgame_forest_showcase --script res://tests/smoke_quest.gd
/path/to/cgame --headless --path misc/cgame_forest_showcase --script res://tests/smoke_combat.gd
/path/to/cgame --headless --path misc/cgame_forest_showcase --script res://tests/smoke_encounters.gd
```

`smoke_combat.gd` verifies real CharacterBody3D pursuit/attack, dormant AI, melee damage and a killed enemy signal. `smoke_encounters.gd` exercises live native cell-root lookup, streamed NPC spawn/despawn, stable defeat ID and saved-state restoration. `smoke_saves.gd` also checks defeated ID round-trips, rejects malformed/duplicate/out-of-world entries and retains compatibility with older v1 saves. `smoke_sources.gd` loads and releases a distant quest scene using an independent source, including updates and cleanup. `smoke_quest.gd` validates nearest-target choice, compass bearing, distance, retargeting and source lifecycle without writing a save. `smoke_streaming.gd` checks motion prefetch before the observer crosses a cell boundary, persistent home-cell pinning and unpinning, async shared-cell load/unload/reload, deterministic per-cell instance transforms, negative grid coordinates, streaming obstacle collision and performance density. `smoke_saves.gd` uses a separate throwaway save path, checking round-trip, deduplication, invalid JSON and version rejection. `smoke_lod.gd` verifies actual near/distant foliage generation, stable transforms across tier switches, pinned hubs retaining full detail, disabling LOD and LOD hysteresis at grid boundaries. `smoke_atmosphere.gd` checks night aurora, sunlight, weather presets, clock wrap-around, pausing, shader uniform updates and the 0.5s sky-work throttle. `smoke_physics.gd` instantiates the real scene, queries static terrain collision and checks that a spawned character falls onto the terrain; it also checks that obstacles are constructed in streamed cells. These tests are **added, not claimed to have been executed**.

## Verification checklist

- [ ] Engine compiles with the new native node, in both tools and template builds.
- [ ] Demo imports and scene starts with no errors on Cgame's Forward+ renderer.
- [ ] Sky shader compiles on Vulkan and Metal (note: `sky()` has no early `return`).
- [ ] Wind, grass instancing and sky render correctly on Apple M1.
- [ ] Test F/left-click combat against stalkers, player hit cooldown and camp respawn, defeated-enemy save/load, no respawn on cell re-entry, and no NPC physics outside the 24m activity radius.
- [ ] Profile CPU physics time with a 5-NPC near-cell limit, confirm raycast occlusion and camera feel on Apple M1/Metal.
- [ ] Verify relic quest beacon and compass after starting, collecting relics and loading a save. Observe that quest source does not keep old cells loaded after retargeting.
- [ ] Check F6/F7/F8 day-night and weather changes in Forward+/Metal, including the sky shader and light probes; compare radiance reprocessing cost at the 0.5-second update interval and frame spikes.
- [ ] Check old v1 save data still loads, and that atmosphere state returns after an explicit save/load.
- [ ] Confirm F4 changes distant tree count and removes/restores distant grass and colliders without duplicates; profile FPS, GPU milliseconds, CPU frame time and VRAM on Apple M1/Metal.
- [ ] Confirm F3 toggles prediction and run a repeated sprint path while comparing scene load delay, FPS and memory usage in both modes.
- [ ] The (0,0) home beacon remains loaded beyond the unload radius; unpinning it allows unloading, and pinning cannot exceed 128 cells.
- [ ] Walking through cell boundaries updates the loaded-cell HUD, preserves terrain/foliage alignment, and unloads/reloads cells without flicker.
- [ ] Verify capsule grounding, jumping, collision against trunks/rocks, world bounds, camera position and save/load after teleporting.
- [ ] Run all nine headless smoke scripts on the compiled fork.
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
- [Unreal Engine Significance Manager](https://dev.epicgames.com/documentation/en-us/unreal-engine/significance-manager-in-unreal-engine)
- [Unreal Engine Character Movement Component](https://dev.epicgames.com/documentation/en-us/unreal-engine/movement-components-in-unreal-engine)
- [Godot MultiMesh optimization](https://docs.godotengine.org/en/stable/tutorials/performance/using_multimesh.html)
- [Godot visibility ranges (HLOD)](https://docs.godotengine.org/en/stable/tutorials/3d/visibility_ranges.html)
- [Godot sky shaders](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/sky_shader.html)
