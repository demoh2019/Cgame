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

## Performance acceptance before shipping

1. On the **same machine, same resolution, same weather and position** (settlement, dense forest, ruined city, storm), capture P50/P95/P99 frame time and peak memory, not just average FPS.
2. Compare preset switches on Compatibility and Forward+, checking sunset sun-disc alignment, shadow stability, water, grass culling and HUD sharpness. Profile GPU and CPU separately.
3. Verify that a low-end preset changes GPU work enough to improve **measured** latency, not merely estimated vertex counts.
4. Ensure asset licensing before importing additional meshes/textures. The game already has graceful fallbacks for absent packs.
5. Run `godot --headless --path game --script res://tests/run_all.gd` with the custom engine fork. The suite includes `test_graphics_quality.gd`, `test_graphics_detail.gd` and `test_sky_lighting_budget.gd`.

**Status:** code-level integration and source invariants are checked. GPU frame time and appearance **must be validated** with an actual build of the custom engine; do not treat profile targets as measured benchmarks.
