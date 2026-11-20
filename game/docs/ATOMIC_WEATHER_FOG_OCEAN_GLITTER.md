# Albion After — physically inspired sun glitter and atomic weather fog

Implemented in the **playable game** and our **native Godot fork** on
the `develop` branch (20 November 2026).

## Ocean sunlight: one more convincing reflection cue

High/Ultra Forward+ render the moving, golden-white broken sun path over
near-camera water. This is an **art-directed microfacet approximation**,
not ray tracing and not a second directional light.

The ocean shader already calculates the surface normal once from two
analytical wave trains, optional wind-driven wave slopes and optional
fine water noise. The sun glitter uses **that same normal** to reflect
the already-published directional-sun vector toward the actual camera:

```glsl
vec3 reflected_sun = reflect(-normalize(aa_sun_to_light), wave_world_normal);
float alignment = max(dot(reflected_sun, to_view), 0.0);
float lobe = pow(alignment, 48.0);
```

A *small*, clamped HDR contribution follows wave crest strength, view
alignment, sun height, local camera distance and foam coverage.
Solar radiance is shared with the time-of-day sky and water scattering,
so night, overcast and storm conditions naturally diminish the path.
The original physically based BRDF/specular reflection, shallow
scattering, whitecaps, glimmer, refraction, wave normals and Fresnel
remain intact.

No new GPU framebuffer, material, reflection probe, texture fetch,
fullscreen pass, water mesh or draw call is created. The whole effect
is inside the already-cached `#ifdef WATER_REFRACTION` shader variant;
the shader used by Performance, Balanced, Compatibility and Mobile
**does not compile the glitter block at all**.

| Quality | Water sun glitter strength | New shader variants | New texture fetches |
| --- | ---: | ---: | ---: |
| Performance | 0 | 0 | 0 |
| Balanced | 0 | 0 | 0 |
| High (Forward+) | 0.38 | 0 | 0 |
| Ultra (Forward+) | 0.80 | 0 | 0 |

High and Ultra reuse the exact same premium material source. Both
read the existing `aa_sun_to_light` and `aa_sun_radiance` shader
globals already set by the real day/night atmosphere and moon/weather
logic at its sky-radiance cadence. The visual is a shader-only
enhancement: no saved gameplay data, physics or authoritative server
changes.

Relevant files:
- `assets/shaders/water.gdshader`: premium-only bounded glint and
  reused per-pixel wave normal.
- `scripts/client/graphics_profiles.gd`: four detail budgets.
- `scripts/client/water_refraction.gd`: existing cached premium
  shader applies the chosen sun glitter strength.
- `tests/test_water_sun_glitter.gd`: no low-end shader regression,
  renderer gates, actual material binding and pure code-budget checks.

## Native Godot optimization — atomic biome and weather fog

Before this change, the game's weather update wrote `fog_light_color`,
`fog_density`, `fog_height`, `fog_height_density` and
`fog_sun_scatter` one after another. Each individual Godot
`Environment` setter invokes `RenderingServer.environment_set_fog()`
with the *entire* fog state. The same frame could thus submit **five
redundant renderer updates** before it finished recomputing the final
sky/biome appearance.

The fork now exposes:

```gdscript
environment.configure_weather_fog(
    color, density, height, height_density, sun_scatter
)
```

The C++ method checks for unchanged values and submits all five
updated parameters in **one** `_update_fog()` call. Individual
property setters also avoid submitting unchanged color/density/height/
sun-scatter states. This improves CPU/RenderingServer submission
efficiency rather than making unsupported GPU speed claims.

`scripts/client/atmosphere.gd` computes the actual sky-derived
horizon color and storm density but no longer writes two intermediate
fog states. `scripts/client/cinematic_fog.gd` then blends the
existing forest/swamp/mountain weather rules against that **base
color**, and calls the native transaction.

If the game is run with a **stock Godot executable**, the script checks
`env.has_method("configure_weather_fog")` and falls back to the same
five regular `Environment` setters. No engine fork is required to
*run* the game (only to gain the optimization). The native method
rejects nonfinite numeric input and does nothing when all five inputs
are unchanged.

Native fork changes:
- `scene/resources/environment.h`: new public method declaration.
- `scene/resources/environment.cpp`: atomic setter, GDScript binding
  and no-op guards for individual fog setters.
- `tests/scene/test_environment_weather_fog.cpp`: native C++
  regression for repeated calls and individual-setter compatibility.
- `tests/test_weather_fog_batch.gd`: live game routing and visual
  state parity, with both native and fallback paths covered.

## How to validate visually and profile the real hardware

```bash
godot --headless --path game --script res://tests/run_graphics.gd
godot --headless --path game --script res://tests/run_all.gd
```

For native C++ tests, build the fork with `tests=yes`, then run its
test executable with the `[Environment]` test case. A headless test
proves API behavior but does **not** measure GPU frame time.

Use *matched* screenshots at a shoreline with the same seed, camera
and saved quality, comparing clear noon, red sunset, heavy storm and
night. On Forward+ compare High/Ultra with low profiles, including
motion across the water. Check that glints follow waves, don't appear
at night, do not blow out whitecaps and remain stable as the camera
moves. Record actual GPU p50/p95 and draw calls in Godot's profiler;
the game's screenshot capture CPU p50/p95/p99 logs alone do not prove
GPU performance.

The native fog transaction should also be profiled via
RenderingServer update counts / CPU frame-time in a scene crossing
forest/swamp biome boundaries. Confirm the fog color transitions
smoothly without cumulative green tint and is not one-frame stale
during heavy rain or lightning.

References:
- [Unreal Engine Lumen rendering and reflection tradeoffs](https://dev.epicgames.com/documentation/en-us/unreal-engine/lumen-global-illumination-and-reflections-in-unreal-engine)
- [Unreal Engine scalable foliage/material models](https://dev.epicgames.com/documentation/unreal-engine/shading-models-in-unreal-engine)
- [Unity HDRP Features](https://github.com/Unity-Technologies/Graphics/blob/master/Packages/com.unity.render-pipelines.high-definition/Documentation~/HDRP-Features.md)
- [Godot environment and postprocess behavior](https://docs.godotengine.org/en/stable/tutorials/3d/environment_and_post_processing.html)

**No measured FPS gain is claimed** until actual GPU or CPU timing on
the target renderer is collected.
