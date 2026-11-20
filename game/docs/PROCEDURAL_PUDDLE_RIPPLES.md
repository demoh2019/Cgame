# Rain puddles: world-space impact ripples without textures

This update extends the **existing physically lit wet ground** instead of
adding a transparent ripple particle layer, extra render pass, offscreen
texture or hundreds of raindrop decals. It works on PBR textured ground and
the game's Compatibility procedural fallback.

## What changes on rainy days

Rain already darkens terrain, reduces roughness and gathers shallow puddles
in swamp mud, dirt roads and aged settlement paving. The new shared
`aa_puddle_ripple_tilt` function generates animated circular rain impacts
in **world metres** inside a 2.6-m grid. Each cell has a stable, cheap
arithmetic-hash phase and a slightly jittered impact centre to prevent an
obvious repeating grid; expanding wavefronts die entirely before the cell
boundary. Adjacent streamed terrain chunks see the *same* pattern with
no geometry seams or texture UV discontinuities.

Impact tilt is mixed into the **surface normal** so the original PBR
lighting, microfacet roughness, reflection probes and (on supported
renderers) screen-space reflections shade each ring naturally.

The ripple field adds **zero texture samples, render passes, particle
emitters or scene nodes** and no per-frame CPU or network traffic.
The code is shared by two ground shaders via
`res://assets/shaders/puddle_ripples.gdshaderinc`.

## GPU scalability

| Quality | Ripple normal strength | Rendering |
| --- | ---: | --- |
| Performance | 0.00 | Branch skips ripple computation entirely |
| Balanced | 0.22 | Subtle nearby wet-road highlights |
| High | 0.65 | Stronger near-field waves |
| Ultra | 1.00 | Full micro-ripple normals |

The shader requires all of these before computing even one impact:
- the preset's ripple strength is positive;
- the pixel is an **actual puddle** (puddle mask > 0.05);
- the world-space distance to camera is inside the existing terrain
  detail radius, smoothly fading near the far limit.

Rainstorm wetness is controlled by the existing
`aa_weather_wetness` uniform; quality strength is one additional shared
`aa_puddle_ripple_strength` GPU uniform updated only when the preset
changes. No per-chunk setter is needed.

## Engine comparisons and rationale

Unity's production-ready Shader Graph weather sample uses dedicated
`RainRipple` and puddle ripple graph components. It warns that rain
weather effects can become among the most expensive shader components,
and describes world-space projection:
https://docs.unity.cn/Packages/com.unity.shadergraph%4017.2/manual/Shader-Graph-Sample-Production-Ready-Weather.html

Unreal Engine's PBR materials accept per-pixel surface normal variation:
https://dev.epicgames.com/documentation/en-us/unreal-engine/material-inputs-in-unreal-engine

Godot documents spatial shader view-space `NORMAL`, `TIME`, and shader
globals:
https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/shading_language.html

The game implements this natively in Godot; it does **not** port another
engine's proprietary shader system.

## Test and QA

The new `res://tests/test_puddle_ripples.gd` is registered in
`res://tests/run_all.gd` and checks quality bounds, shader registration,
shared includes, near/dry pixel guards, zero extra texture reads,
world-space seam handling and PBR/fallback integration.

```sh
godot --headless --path game --script res://tests/run_all.gd
```

Compare clear versus storm at the exact same swamp and road camera points;
check ring movement under the sun, shadow, and at night, and check each
graphics preset. Confirm no seams where neighboring chunks meet and use
GPU profiling before claiming a frame-time improvement.
