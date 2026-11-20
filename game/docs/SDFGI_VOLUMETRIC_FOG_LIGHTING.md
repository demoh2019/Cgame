# SDFGI illumination of volumetric fog (Ultra)

Albion After's premium Forward+ lighting path now injects a small amount of
**existing native SDFGI bounced light** into its already-allocated volumetric
froxel grid. This provides spatially varying illumination around static world
geometry, under overhangs and in ruins, including bounced light from surfaces
outside the current camera view.

## Preset and rendering budget

| Graphics tier | SDFGI field | Fog GI weight | Extra renderer pass |
| --- | --- | --- | --- |
| Performance | Off | 0 | None |
| Balanced | Off | 0 | None |
| High | Off | 0 | None |
| Ultra (Forward+) | 2 cascades | 0.24 | No extra fog pass |
| Ultra (Compatibility/Mobile) | Off | 0 | None |

The GI term is evaluated within the existing Godot volumetric fog pass. GPU
cost **is not zero**: when weight is above zero, the fog shader samples
indirect-light data. The low strength preserves atmospheric contrast instead
of replacing direct sun scattering or the artist's AgX color grade.

The runtime checks `Environment.sdfgi_enabled` before injecting to avoid
sampling missing GI resources during initial scene setup, quality changes or
renderer fallback. The same `CinematicFog` profile is applied by the actual
online/offline quality pipeline; no extra fog-volume nodes, reflection probes,
network messages or simulation state are created. Dynamic GI and storm/fog
weather continue to use their established update cadence.

The custom Cgame `Environment.set_volumetric_fog_gi_inject()` now rejects
NaN/inf/negative inputs and skips exact repeat values, reducing
`RenderingServer` state changes as Auto graphics presets are reapplied.

## Verification

Godot regression: `game/tests/test_cinematic_fog.gd`, registered in both
`game/tests/run_all.gd` and `game/tests/run_graphics.gd`.
Native C++ regression: `tests/scene/test_sky.cpp`.
Run with the rebuilt Cgame Godot fork:

```sh
godot --headless --path game --script res://tests/run_graphics.gd
```

Visually compare High and Ultra with fixed camera, weather, exposure and
resolution in woods, ruins, foggy coastal areas and bunkers. Profile p50/p95
GPU frame time and unified memory on Apple M1; verify no light leaks, extra
volumetric ghost trails, or stale brightness after changing tier. A passing
source-level assertion is **not** a substitute for rendering benchmarks.

References:
- Godot: https://docs.godotengine.org/en/stable/tutorials/3d/volumetric_fog.html
- Godot: https://docs.godotengine.org/en/stable/tutorials/3d/global_illumination/using_sdfgi.html
- Unity HDRP lighting: https://docs.unity.cn/Packages/com.unity.render-pipelines.high-definition%408.0/manual/Subsurface-Scattering.html
