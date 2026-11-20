# Albion After: graphics quality and frame budget

The canonical game scene is `game/scripts/client/online_main.tscn`. All visual tuning is **client-only**; authoritative movement, combat, loot and world generation remain unchanged.

## Lessons adapted from other renderers

- **Unreal Engine Nanite**: stream and simplify geometry instead of drawing distant triangles at full detail. In this engine fork we use `WorldStreamer`, `ChunkedTerrain3D`, grass mesh LOD and MultiMesh rather than claiming to have implemented Nanite.
  [Unreal Nanite documentation](https://dev.epicgames.com/documentation/en-us/unreal-engine/nanite-virtualized-geometry-in-unreal-engine)
- **Unity 6 URP GPU Resident Drawer**: large numbers of similar objects should be batched and culled efficiently. Our foliage is grouped into MultiMeshes with distance limits; keep additional object types instanced where possible.
  [Unity GPU Resident Drawer](https://docs.unity3d.com/6000.0/Documentation/Manual/urp/gpu-resident-drawer.html)
- **Godot 4 sky radiance caching**: a sky shader that uses built-in `TIME` or `LIGHT0_*` often causes cubemap updates every frame. We now upload cached animation/sun uniforms at a bounded rate and use `Sky.PROCESS_MODE_INCREMENTAL`.
  [Godot sky shader docs](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/sky_shader.html)
- **Godot 3D upscaling**: use per-renderer FSR2/FSR options where available; keep the HUD at its native screen resolution.
  [Godot resolution scaling](https://docs.godotengine.org/en/stable/tutorials/3d/resolution_scaling.html)

## Integrated controls

`graphics_quality.gd` keeps the four user-facing presets and saves the choice locally. `graphics_profiles.gd` contains additional world budgets; do not introduce another preferences file.

| Profile | Sky radiance | Minimum time between sky refreshes | Grass fade end | Water |
| --- | ---: | ---: | ---: | --- |
| Performance | 32 | 0.70 s | 40 m | Stationary normals; avoids animated multi-octave normal noise |
| Balanced | 64 | 0.50 s | 56 m | Moderate animated ripples |
| High | 64 | 0.30 s | 60 m | Detailed animated ripples |
| Ultra | 128 | 0.20 s | 75 m | Stronger water normal variation |

Sky refreshes are **maximum scheduling frequency**, not guaranteed rendered cubemap frames. The GPU may process incremental filtering across several frames. The directional light rotation and storm fog are updated normally every game frame; only the **sky's baked radiance and sun disc uniforms** update on the selected interval. Preserve this separation when changing `atmosphere.gd`.

## Spatial instance culling and screen-space mesh LOD

Our dense natural-world content uses the same two complementary techniques as Unreal HLOD and Unity LOD Groups, without pretending to implement either feature identically:

- **Per-model MultiMesh** continues to batch meshes into few draw calls. `object_batch_grid.gd` divides only dense groups of trees/rocks/ore (at least 12 copies of the same mesh in a chunk) into up to four spatial cells. Sparse decorations, structures and crates remain unpartitioned, avoiding unnecessary draw calls and preserving critical landmarks.
- **Screen-space mesh LOD** uses `Viewport.mesh_lod_threshold`, already implemented in the custom Cgame engine fork. Imported glTF scenes with generated LODs can select cheaper triangle counts sooner as objects shrink on screen. This does **not** decimate procedural meshes or generate Unreal Nanite clusters.
- Per-batch IDs are **visual-only**, while each node retains its world-generated server ID. Depleted resources and opened crates still use the original server-driven hidden-state logic.
- Quality thresholds (in pixels; higher = more aggressive decimation): **Performance 4.0**, **Balanced 2.0**, **High 1.0**, **Ultra 0.75**. The setting is applied to the active viewport with the existing graphics presets.

This follows Godot's recommendation to split MultiMeshes by spatial proximity because their LOD choice and culling operate on the whole batch's bounding box. A profile switch changes the LOD threshold immediately; old chunks are not rebuilt until they leave and reenter streaming.

**Performance caveat:** splitting a batch can increase the number of draw calls if all cells are simultaneously visible. This is why groups with fewer than 12 instances stay together and only selected dense natural assets are partitioned. Compare dense forest and open fields before accepting a GPU performance gain.

[Godot mesh LOD](https://docs.godotengine.org/en/stable/tutorials/3d/mesh_lod.html) |
[Unreal HLOD](https://dev.epicgames.com/documentation/unreal-engine/hierarchical-level-of-detail-in-unreal-engine) |
[Unity LOD Groups](https://docs.unity.com/en-us/engine/6000.0/manual/analysis/graphics-performance-profiling/simplifying-distant-meshes-with-level-of-detail-lod/class-lodgroup)

## Global dungeon light budget (Unity/Unreal-style local light prioritization)

Each procedural dungeon room has an atmospheric warm torch, but loading many rooms at once should **not** register every torch as an active GPU light. `dungeon_light_budget.gd` is a single scene-level manager shared across all streamed chunks:

- Streamed `OmniLight3D` torches enter the `aa_dungeon_torches` group **invisible**. The manager checks candidate distance every 0.13 seconds, selects the nearest lights globally, and turns only the selected ones on. Unselected or unloaded lights contribute no GPU work.
- The light's energy fades smoothly as it approaches the visibility radius. Two low-frequency sine waves create subtle fire flicker without per-frame CPU randomization. Light distance fade is enabled as an additional GPU-side transition.
- On **Forward+** only, High may have one dynamic-shadow torch and Ultra two; lower-quality presets and Compatibility have no local shadow maps. On Compatibility, the global active-light count is capped at eight even when Ultra is selected. The main directional light and gameplay lighting remain separate.
- No world-generation IDs, server packets, dungeon layout or hitboxes are altered. In contrast to baked lightmaps this works with the procedurally streamed world.

| Profile | Active torch lights (global cap) | Range around camera | Local shadow casters |
| --- | ---: | ---: | ---: |
| Performance | 3 | 28 m | 0 |
| Balanced | 6 | 44 m | 0 |
| High | 10 | 62 m | 1 (Forward+) |
| Ultra | 16 | 84 m | 2 (Forward+) |

`test_dungeon_light_budget.gd` verifies pure nearest-light selection, limits, soft fade, and shadow budgets. Verify both **bright/dark dungeon readability** and **P95 GPU and CPU frame times** in heavily streamed underground halls before accepting the effect.

Reference: [Godot 3D lights and shadows](https://docs.godotengine.org/en/stable/tutorials/3d/lights_and_shadows.html); [Unity URP Forward+ additional lights](https://docs.unity3d.com/Packages/com.unity.render-pipelines.universal@15.0/manual/rendering/forward-plus-rendering-path.html).

## Procedural occlusion culling in streamed dungeons

Following **Unreal visibility/occlusion culling** and **Unity static occluders**, `dungeon_occlusion.gd` now generates one conservative `BoxOccluder3D` inside each suitable **solid** wall mesh of the underground kit. Doors and columns never generate an occluder. The largest eligible individual mesh is used rather than the whole wall's merged bounding box to avoid accidentally closing gaps. Every box is shrunk on all axes (especially vertically, because the camera looks over low walls).

`game/project.godot` enables the built-in software occlusion infrastructure, and `online_main.gd` switches `Viewport.use_occlusion_culling` **only underground** on the Forward+ or Mobile rendering methods and graphics levels Balanced/High/Ultra. On Performance, Compatibility and everywhere above ground, the viewport keeps occlusion **off** to avoid unnecessary CPU rasterization. A graphics-preset change or leaving the dungeon automatically reevaluates the flag. Occluders are static after their streamed chunk is built; no runtime BVH rebuilds for moving props.

This system does not replace frustum culling, mesh LOD or streaming. It also does not promise improvement in a cave where the top-down camera sees over every wall; screen-space effectiveness depends on how much geometry is actually hidden. To validate, compare the same underground view with Performance and High/Ultra, then toggle `use_occlusion_culling` on the root viewport while recording CPU P95 and GPU draw calls. Visual regressions to check: open doorways, low walls, loot visibility and the player model.

References:
- [Godot occlusion culling setup and limitations](https://docs.godotengine.org/en/stable/tutorials/3d/occlusion_culling.html)
- [Unreal Engine visibility and occlusion culling](https://dev.epicgames.com/documentation/en-us/unreal-engine/visibility-and-occlusion-culling-in-unreal-engine)
- [Unity static occluders and dynamic occludees](https://docs.unity.com/en-us/engine/6000.3/manual/cameras/occlusion-culling/getting-started)

## Performance acceptance before shipping

1. On the **same machine, same resolution, same weather and position** (settlement, dense forest, ruined city, storm), capture P50/P95/P99 frame time and peak memory, not just average FPS.
2. Compare preset switches on Compatibility and Forward+, checking sunset sun-disc alignment, shadow stability, water, grass culling and HUD sharpness. Profile GPU and CPU separately.
3. Verify that a low-end preset changes GPU work enough to improve **measured** latency, not merely estimated vertex counts.
4. Ensure asset licensing before importing additional meshes/textures. The game already has graceful fallbacks for absent packs.
5. Run `godot --headless --path game --script res://tests/run_all.gd` with the custom engine fork. The suite includes `test_graphics_quality.gd`, `test_graphics_detail.gd`, `test_object_batch_grid.gd`, `test_dungeon_light_budget.gd`, `test_dungeon_occlusion.gd` and `test_sky_lighting_budget.gd`.

**Status:** code-level integration and source invariants are checked. GPU frame time and appearance **must be validated** with an actual build of the custom engine; do not treat profile targets as measured benchmarks.
