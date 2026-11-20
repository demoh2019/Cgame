# Directional sunset haze and sky radiance fidelity

## Industry references

Unreal's Sky Atmosphere calculates angular scattering for sunward aerial
perspective rather than painting a flat orange band along the horizon. Godot
also draws its sky into a cubemap used by physically based reflections and
ambient illumination. This change adapts one **cheap aerosol phase lobe**
to the game's existing stylized HDR sky; it does not implement Unreal's full
multiple-scattering atmosphere or volumetric cloud system.

- Unreal: https://dev.epicgames.com/documentation/unreal-engine/sky-atmosphere-component-in-unreal-engine
- Godot: https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/sky_shader.html
- Godot radiance: https://docs.godotengine.org/en/stable/classes/class_sky.html

## What is implemented in the live game

- `assets/shaders/sky.gdshader` now computes a **forward aerosol scattering**
  term from the actual sun direction using a bounded Henyey-Greenstein-like
  phase expression. The sunward sky gets diffuse atmospheric glow rather than
  only a sharp painted disc. Sunsets tint this glow warm; high noon keeps a
  subtle blue haze, and storm clouds suppress it.
- The new term fades gradually with sky elevation and solar daylight, so
  there is no orange haze under a moonlit sky. The old narrow halo is
  attenuated as the improved one takes over; the panorama, anti-aliased
  stars, moonlight and original sun disc are all retained.
- Crucially, both the **visible sky** and the **radiance cubemap** execute
  the same scattering model. Brushed metal, water and other PBR surfaces
  therefore reflect a sky that matches its visually warmer horizon.
- The quality setting is a single shader uniform applied when the user
  changes presets. There are no new textures, framebuffer passes, rays or
  meshes. The shader uses reciprocal square root instead of an expensive
  general power for its aerosol angular distribution.
- The existing `sky_use_cached_radiance` flag was present in all graphics
  profiles but `graphics_quality.gd` did not actually send it to
  `Atmosphere`. This is now connected: Performance/Balanced can sample
  Godot's periodically refreshed sky cubemap as the background, while
  High/Ultra retain the full-resolution panorama and pinprick stars.
  Sky radiance updates remain bounded by their existing profile cadence.

| Preset | Aerosol scattering | Visible background | Sky radiance update interval |
| --- | ---: | --- | ---: |
| Performance | 0.00 | Cached sky | 0.70 s |
| Balanced | 0.35 | Cached sky | 0.50 s |
| High | 0.70 | Full resolution | 0.30 s |
| Ultra | 1.00 | Full resolution | 0.20 s |

## Validation

Run the existing full Godot headless import and test scripts from the
repository root:

```sh
godot --headless --editor --path game --quit
godot --headless --path game --script res://tests/run_all.gd
```

`test_sky_aerosol_scattering.gd` checks all profile settings, sky shader
dependency/caching rules and live Atmosphere wiring. The current editing
environment has no Godot runtime, so these tests have been added but not
executed here.

Visual A/B in the game at the *same position and time*:
1. Sun near horizon: the warm scattering should concentrate **toward** the
   sun and vary gently along the horizon, without orange at midnight.
2. Midday clear sky and storm: preserve blue midday lighting, color
   readability, the existing licensed panorama and storm desaturation.
3. Metallic props and water: reflected sky should follow visible golden
   hour tones rather than showing contradictory cold highlights.
4. Compare Performance/Ultra on Forward+ and Compatibility, including
   visible sky refresh cadence and temporal changes during movement.

Measure p50/p95 GPU time and sky cubemap refresh cost across identical
weather/lighting before claiming FPS gains. Extra high-quality scattering
does cost several ALU instructions per sky pixel. The low-end skip and
cubemap fast path should avoid that overhead, but require runtime profiling.
