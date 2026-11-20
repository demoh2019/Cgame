# World-stable 3D volumetric mist — game and native Godot renderer

## Renderer references

Unreal Engine Local Fog Volumes and Unity HDRP Local Volumetric Fog combine
nonuniform density masks with froxel lighting. Godot Forward+ uses a matching
volume-based fog path, so we improve our existing player-centered FogVolume
rather than allocating an additional translucent pass or extra fog nodes.

- Unreal: https://dev.epicgames.com/documentation/unreal-engine/local-fog-volumes-in-unreal-engine
- Unity HDRP: https://docs.unity.cn/Packages/com.unity.render-pipelines.high-definition@17.1/manual/create-a-local-fog-effect.html
- Godot: https://docs.godotengine.org/en/stable/tutorials/3d/volumetric_fog.html

## Game: genuine vertical mist layers

Albion After already had a bounded, world-aligned, camera-following fog volume
for forest, swamp and coastal biomes. It used two 2D noise scales, sunlight,
rain and local ground-height density falloff. It now adds a *third* volumetric
noise field on Ultra: 8-corner 3D value noise with height as an independent
axis, plus a broad low-frequency wind bend, for naturally curling vapor
ribbons instead of the same 2D shape being repeated at every altitude.

This new octave is gated by `vapor_3d_detail` in the **same existing fog
shader**; the shader never samples a 3D texture or calls another render
pass. It preserves world alignment, wind advection, high/low altitude
fade, weather-aware density and original soft box-edge falloff.

| Graphics | Added 3D octave | Notes |
| --- | ---: | --- |
| Performance | 0 / none | no local FogVolume or extra shader work |
| Balanced | 0 / none | no local FogVolume or extra shader work |
| High Forward+ | 0 | pre-existing 2D mist, unchanged cost |
| Ultra Forward+ | 0.55 | one additional 3D noise octave |
| Compatibility / Mobile | 0 / none | original fog, no local froxels |
| Dungeon / mountain | 0 / disabled | combat visibility maintained |

The 3D octave is **not free**: each evaluated Ultra froxel does eight
procedural hash samples. The volume remains only 88 × 14 × 88 m with fading
at its edges. Shared native Forward+ froxel quality is still controlled by
the existing CinematicFog profile, including GI injection and temporal
reprojection. This update adds no new full-screen pass and no texture bytes.

## Engine: stable local fog placement

In the custom Godot fork, FogVolume adds:

- `FogVolume.snap_world_anchor(world_position, grid_step)`: pure XZ grid
  snapping that leaves the vertical position unchanged.
- `FogVolume.set_snapped_world_anchor(world_position, grid_step,
  distance_epsilon=0.1)`: validates all inputs and skips duplicate
  global-transform uploads within a small epsilon; returns whether moved.
- `FogVolume.set_size` now rejects NaN/Infinity before they can corrupt
  froxel culling AABBs.

The game calls the native API for the existing 8 m world grid when
available; unmodified stock Godot uses its previous GDScript snapping.
No scene serialization or default FogVolume behavior is changed.

## Validation

C++: run tests tagged `[SceneTree][FogVolume]`, including finite size
behavior and world-grid snapping for positive/negative positions.

Game: `godot --headless --path game --script res://tests/run_all.gd`;
`test_ground_mist.gd` now checks shader source, 3D noise quality gating,
native integration and online/offline shared components.

Visual profiling:
1. Compare swamp forest mist in High and Ultra at sunrise and during storms;
   inspect actual vertical fog depth from a low camera angle.
2. Walk slowly across an 8 m snap boundary; watch for ghost trails or
   square volume edges and keep HUD/near enemies readable.
3. Compare low-end Compatibility, Performance, dungeons and mountains.
4. Measure froxel GPU p50/p95 and fog passes on High versus Ultra on real
   Apple M1 hardware. Lower `vapor_3d_detail` or local fog range if expensive.

Static source checks establish integration only. Compiling the fork, shader
compilation and GPU measurements still require an environment with Godot.
