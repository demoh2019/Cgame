# Rain VFX: GPU simulation with a Compatibility fallback

The old multiplayer rain system was **one CPUParticles3D emitter with 700
always-allocated streaks**, using a 12-triangle BoxMesh for every drop.
It did not scale its particle count with the player's graphics preset.

The rain renderer now uses **one camera-local GPUParticles3D emitter on
Forward+ and Mobile**, and one lower-budget CPUParticles3D emitter on
Compatibility or unknown backends. No rain particles affect survival,
collision, world generation, server authority or network packets.

## Fidelity / performance

Each drop uses a camera-facing **QuadMesh with two triangles** instead
of the former 12-triangle box. The unlit, translucent streaks retain the
original cool-blue raindrop palette and height/speed of the storm. A
simple alpha gradient fades streaks in and out without extra textures.

| Quality | GPU particle capacity | Compatibility CPU capacity |
| --- | ---: | ---: |
| Performance | 160 | 55 |
| Balanced | 460 | 110 |
| High | 850 | 210 |
| Ultra | 1350 | 320 |

`amount` is changed only when the graphics preset changes, so the GPU
emission buffers are not reallocated at 60 fps. Actual rain intensity
uses `GPUParticles3D.amount_ratio`; this changes continuously without
restarting the emitter. **Reducing `amount_ratio` does not shrink the
allocated GPU budget**, so the preset caps above still matter. The CPU
fallback changes alpha with drizzle intensity and keeps a low fixed
allocation, avoiding a CPU emitter restart every weather frame.

A conservative 54 x 43 x 54 m particle visibility AABB covers the
camera-following rain volume and downward travel. Existing particles
stay in world space when the camera moves. Rain casts no shadow maps.

The existing online `Effects.update_rain` call feeds smoothed storm
intensity. The offline playable preview now spawns the same renderer
and also updates it with its local world weather. Both respond to the
existing graphics presets; **Ctrl+F11** switches the local preview tier.

## Implementation

- `res://scripts/client/rain_vfx.gd`: profile budgets, GPU/CPU factory,
  smooth storm density and quality application
- `res://scripts/client/effects.gd`: live multiplayer connection
- `res://scripts/client/client_main.gd`: playable offline integration
- `res://tests/test_rain_vfx.gd`: clamping, scaling, real particle node
  properties, no restart on rain-intensity updates, engine fallback,
  both-client integration

Run the main test suite when Godot is available:

```sh
godot --headless --path game --script res://tests/run_all.gd
```

For visual and GPU QA, capture **exactly the same camera location**
in clear/drizzle/full storm, repeat in Forward+ and Compatibility at all
four presets, profile average and p95 frame times, confirm neither
rain nor accumulated precipitation pops during camera movement.

## Engine design references

- Unreal Niagara scalability and effect budgets:
  https://dev.epicgames.com/documentation/en-us/unreal-engine/scalability-and-best-practices-for-niagara
- Unity VFX Graph bounds and culling:
  https://docs.unity.cn/Packages/com.unity.visualeffectgraph%4017.4/manual/visual-effect-bounds.html
- Godot GPUParticles3D `amount_ratio`, backend-dependent GPU/CPU
  considerations, and `visibility_aabb`:
  https://docs.godotengine.org/en/stable/classes/class_gpuparticles3d.html

This is a native Godot particle renderer, not a reimplementation
of Unreal Niagara or Unity VFX Graph. No FPS gain is asserted until
measured on a running game build.
