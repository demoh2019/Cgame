# Procedural moon, lunar phases and night-sky PBR — Albion After

## Industry references

- Unreal Sky Atmosphere provides a second celestial body / moon directional
  light; our Godot renderer reuses the existing directional light after sunset
  instead of allocating an additional light pass:
  https://dev.epicgames.com/documentation/en-us/unreal-engine/sky-atmosphere-component-in-unreal-engine
- Unity HDRP celestial bodies support automated moon phases:
  https://docs.unity.cn/Packages/com.unity.render-pipelines.high-definition@17.1/manual/HDRP-Sample-Content.html
- Godot sky shaders render both the background and the radiance cubemap
  used by image-based PBR reflections:
  https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/sky_shader.html

This is an **artistic, lightweight** sky model, not physically accurate
lunar ephemeris or Unreal's full atmospheric scattering pipeline.

## What is integrated

- `scripts/client/moon_visuals.gd` derives a deterministic lunar phase from
  **authoritative shared world time**, using the existing 900-second day
  length and a 29.530588-day synodic cycle. This makes the moon consistent
  between the multiplayer world and the playable local preview, without
  synchronizing any new game/server packet. A fresh world begins near full moon.
- `assets/shaders/sky.gdshader` now blends out the large solar disc at dusk
  and renders an **antialiased rounded moon** after dark. A curved terminator
  produces new, quarter, gibbous and full phases. The night-side earthshine
  remains subtle; three diffuse, procedural maria add lunar surface detail.
- The moon, halo and its changing reflected radiance use the **existing sun
  direction**, which is already repurposed as moonlight after sunset.
  Sky cubemap reflections and visible sky stay consistent.
- Clouds/storms reduce moon visibility, dawn smoothly blends to sunlight,
  and moonlight's directional brightness varies gently with lunar
  illumination. The existing blue ambient night fill stays unchanged, so
  a new moon does **not** make the game unreadably dark.
- High-quality surface shading only runs for pixels inside the tiny
  angular cone around the moon. No new textures, mesh instances,
  fullscreen passes or extra light sources are introduced. The existing
  incremental sky cubemap refresh cadence is preserved.

| Preset | Moon surface detail | Visible sky |
| --- | ---: | --- |
| Performance | Off | Cached radiance |
| Balanced | 0.35 | Cached radiance |
| High | 0.70 | High-resolution night sky |
| Ultra | Full | High-resolution night sky |

The settings apply through `graphics_quality.gd` to the shared Atmosphere,
with no gameplay/server-side changes.

## Verification and acceptance

`game/tests/test_procedural_moon.gd` covers synchronized phase mathematics,
waxing/waning illumination, lunar shader invariants, GDScript integration
and the four graphics presets.

Run from the repository root on a machine with Godot:

```sh
godot --headless --editor --path game --quit
godot --headless --path game --script res://tests/run_all.gd
```

Visual A/B: at identical world time and camera angle, compare full moon and
first/last quarter; inspect anti-aliasing as the camera moves, dark-side
earthshine and cloud occlusion; verify the same phase in offline and online
preview. Compare mirrored PBR water and metal under full/new moon. Test both
Forward+ and GL Compatibility. Measure sky shader GPU time and cubemap
refresh cost at Performance/High/Ultra; no FPS benefit is claimed until
measured on physical hardware.

**Limitations:** Lunar geometry is an artist-friendly approximation, not
a real astronomical simulation; the phase follows world days and does not
include eclipses, orbital tilt or geographically accurate rise times.
The local editing environment does not have the Godot executable to run
shader compilation or frame-time measurements.
