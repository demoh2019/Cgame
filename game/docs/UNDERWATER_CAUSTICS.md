# Physically lit shallow-water caustics in Albion After

This feature projects moving sunlight filaments onto submerged sand, rock
and lakebeds. It is integrated into **both real game terrain pipelines**:
the 13-layer Poly Haven PBR ground and its procedural, texture-independent
fallback. It is not a demo overlay.

## Visual design

Both shaders include `res://assets/shaders/water_caustics.gdshaderinc`.
The include analytically creates two distorted crossing wavefronts in
**world metres**. All streamed chunks and material transitions share the
same pattern; no UV seams, material instances, decals or additional meshes
are created.

The caustics appear only on terrain beneath the game's actual water mesh
(`Defs.WATER_LEVEL - 0.35`), within 4.5 m of the water surface, on
upward-facing ground and within 48 m of the camera. The broad central
light pattern smoothly fades near the shoreline depth, in deep water and
with distance. Color is added to the existing **PBR albedo**, so existing
physically based lighting, normal maps, specular roughness and sky/fog
remain authoritative rather than introducing unrealistic unlit emission.

The source sunlight comes from the actual world clock. Rain clouds
reduce the direct light to approximately 8% of clear midday; low
sunset and night disable the effect. The game updates this scalar only
**five times per second**, never for individual chunks.

## Performance budgets

| Tier | Caustic strength on Forward+ | Shader cost |
| --- | ---: | --- |
| Performance | 0 | Uniform branch skips all procedural caustic work |
| Balanced | 0 | Same zero-cost fallback |
| High | 0.55 | One animated near-field wave network |
| Ultra | 1.00 | One primary and one offset fine caustic network |

Mobile and Compatibility always set this GPU uniform to zero, regardless
of the user's requested graphics tier. There are **no additional texture
fetches, render targets, screen-space passes, scene nodes or imported
textures**. GPU ALU is only spent on submerged and visible nearby ground
at High or Ultra. The caustic intensity stays bounded to [0, 1].

As an engine-level rendering extension, the effect exposes two shader
globals in `game/project.godot`: `aa_water_caustics_strength` (quality,
written on quality changes) and `aa_water_caustics_sun` (day/night,
updated at most 5 Hz). This reuses the game's existing quality and
weather systems without network or gameplay changes.

## Engine references

- Godot spatial shader PBR materials and per-pixel normals:
  https://docs.godotengine.org/en/4.5/tutorials/3d/standard_material_3d.html
- Unreal Engine's Light Function Atlas explicitly supports projected
  caustic patterns and explains how to batch light functions:
  https://dev.epicgames.com/documentation/unreal-engine/using-light-functions-in-unreal-engine
- Unity HDRP computes caustics on opaque geometry visible through water;
  its simulation-based caustics are more costly than our near-field pattern:
  https://docs.unity.cn/Packages/com.unity.render-pipelines.high-definition%4017.0/manual/WaterSystem-caustics.html
- GPU Gems documents techniques for believable animated water caustics:
  https://developer.nvidia.com/gpugems/gpugems/part-i-natural-effects/chapter-2-rendering-water-caustics

This is a native Godot shader implementation; no proprietary
Unreal/Unity rendering pipeline is copied.

## Verification

```sh
godot --headless --path game --script res://tests/run_graphics.gd
godot --headless --path game --script res://tests/run_all.gd
```

`res://tests/test_water_caustics.gd` validates sunlight/weather inputs,
quality and renderer clamping, correct sea level, both terrain shaders,
world-space continuity, near/deep-water culling and the absence of
additional texture reads. For actual QA, inspect sandy and rocky
shallows at noon, dawn, night and storm using the same camera. Record
average/p95 GPU frame times before claiming performance improvements.
