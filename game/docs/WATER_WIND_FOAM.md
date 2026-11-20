# Wind-advected premium water foam (Albion After + native LOD correction)

## Why

Unity HDRP's water system builds wind-dependent foam, with separate
simulation controls for calm and windy conditions. Unreal Water Body Actors
also use wind-driven/flowmap-guided motion. Albion After already had
depth-dependent coast foam, storm crests, nearshore surf, refraction,
single-scattering and wind-oriented GGX highlights, but its deep-water
whitecaps relied mostly on the local analytic slope magnitude.

This update adds **thin, broken foam ribbons** travelling in the real wind
direction, while correcting the fork's geometry quality response to
dynamic 3D render scale.

## Implementation

The premium `water.gdshader` variant (High/Ultra on Forward+) adds a
`wind_foam_strength` uniform and a world-aligned procedural ribbon pattern:

- Along-wind wave phase advects with game `TIME` and weather strength.
- Across-wind sinusoids break ribbons instead of creating straight bands.
- The new term reuses **existing wind, storm, crest, water depth, foam,
  camera detail fade, and color/roughness/alpha** calculations.
- Branches skip all extra trigonometry when the wind is calm, water too
  shallow or the camera beyond the near-field detail budget.
- No extra noise textures, depth/color samples, passes, geometry, particle
  simulations or transparent surfaces are introduced.
- The low shader variant has its premium code excluded by `WATER_REFRACTION`
  preprocessor guards, preserving Compatibility and Performance.

| Quality | Wind foam |
| --- | ---: |
| Performance | 0.00 — absent |
| Balanced | 0.00 — absent |
| High Forward+ | 0.20 |
| Ultra Forward+ | 0.42 |

The pattern is intentionally a stylized procedural approximation of
wind fetch rather than a physical water simulation. It is masked by
wind and depth and requires gameplay capture to evaluate aesthetics.

## Native engine improvement

The existing `ChunkedTerrain3D.screen_space_lod_enabled` selector used
the **window** height when scaling geometry distance thresholds.
For dynamic resolution and FSR, this can retain costly extra terrain
geometry even when the engine renders fewer 3D pixels.

The selector now multiplies `viewport_size.y` by
`Viewport.get_scaling_3d_scale()`, matching the engine's independent,
existing `lod_pixel_error` implementation. This changes no collision,
mesh buffers, screen shaders, or LOD cache. It only selects the same
cached terrain meshes based on **actual internal 3D resolution**. A
720-pixel viewport at 70% scale has about 504 internal 3D pixels.
Legacy distance-only LOD and user-hidden `screen_space_lod_enabled=false`
are unaffected.

## Verification

Headless tests:
`godot --headless --path game --script res://tests/run_all.gd`

The game test `test_water_wind_foam.gd` verifies tier budgets, premium
shader compilation gates, camera fading, reuse of water shading, live
material quality switches and Compatibility fallback.

The engine C++ test `[HeightmapTerrain] Screen-relative terrain LOD
preserves pixels and FOV` includes dynamic 3D-scale numerical cases.

Actual GPU verification:
1. Record windy lakeshore and open water at High/Ultra, at sunset and
   during storms. Check for repetitive or screen-swimming foam patterns.
2. Check calm water and Performance/Compatibility remain unchanged.
3. Toggle adaptive 3D scale (1.0 / 0.7) near mountain ridges; ensure
   the screen-relative LOD responds and native pixel-error LOD still
   uses actual internal pixels.
4. Compare p50/p95 GPU frame-time and any visual popping on real hardware.

No compiled Godot or hardware frame-time measurements were available
while authoring; this is code integration, not a measured FPS claim.

References:
- https://docs.unity.cn/Packages/com.unity.render-pipelines.high-definition@17.6/manual/water-capabilities-of-the-water-system.html
- https://dev.epicgames.com/documentation/unreal-engine/water-body-actors-in-unreal-engine
- https://docs.godotengine.org/en/stable/tutorials/shaders/screen-reading_shaders.html
