# Sky cirrus layer driven by a shared cached cloud LUT

## What changed in the playable game

The sky material now renders a subtle, wind-aligned high cirrus layer over the
existing panorama (or fallback gradient). It follows the same smooth weather
wind as the terrain cloud shadows. Sun-facing wisps warm at golden hour; at
night they darken stars. Storms mute the white highlights. The sky remains
visible in the radiance cubemap, so PBR reflections follow the same lighting.

The layer reuses `CloudShadowLut.texture()`, the existing **128×128 R8**
texture created for terrain and foliage. There are **no new textures, CPU
noise builds, mesh nodes, or full-screen post-processing passes**.

| Quality | LUT taps per procedural sky pixel | Layer opacity | Visible sky |
| --- | ---: | ---: | --- |
| Performance | 0 | 0 | cached 32 px cubemap |
| Balanced | 1 | 0.22 | cached 64 px cubemap |
| High | 1 | 0.38 | full-resolution panorama |
| Ultra | 2 | 0.52 | full-resolution panorama |

The sky shader executes these samples only above a small horizon threshold.
It never uses Godot's camera `POSITION` or built-in `TIME`, because both
can invalidate cached sky reflections too frequently. Wind upload remains
bounded by the existing `sky_refresh_interval`; the texture is never
regenerated when the wind changes. Color and cloud detail are local visual
controls; simulation, gameplay wind, and network state do not change.

## Engine and integration

Godot's existing Sky/ShaderMaterial/RADIANCE infrastructure already supports
this effect; no custom engine C++ change is necessary. The engine remains the
owner of sky cubemap filtering, reflection sampling, exposure, and rendering.
The game configures the feature through `graphics_profiles.gd`,
`graphics_quality.gd`, and `atmosphere.gd`.

Compare with Unreal's efficient cloud shadow maps and Unity HDRP's scalable
volumetric fog. This is an intentionally **cheap 2D upper-cloud layer**,
not a claim to implement full volumetric multiple scattering.

- https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/sky_shader.html
- https://dev.epicgames.com/documentation/en-us/unreal-engine/volumetric-cloud-component-in-unreal-engine
- https://docs.unity3d.com/Packages/com.unity.render-pipelines.high-definition@latest/

## Verification

Run `godot --headless --editor --path game --quit`, then
`godot --headless --path game --script res://tests/run_all.gd`.
The added `test_sky_cirrus_lut.gd` checks presets, quality wiring,
night/cloud lighting, shared LUT binding, shader fast paths and sky caching.

On an actual GPU compare camera movement, noon, dusk, storm, and night, both
Forward+ and Compatibility. Record P50/P95 GPU frame times and actual radiance
updates before drawing performance conclusions; one extra LUT sample is not
guaranteed to improve FPS on every device.
