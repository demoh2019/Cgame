# Ultra dynamic global illumination in Albion After

Ultra now uses two-cascade SDFGI in Forward+ with 0.5 m cell size (up to about 128 m), 0.32 bounce feedback, 0.72 energy and sky contribution. SSAO remains enabled, while the overlapping SSIL pass is disabled. Lower tiers, Mobile and Compatibility have SDFGI disabled. Half-resolution GI buffers reduce bandwidth, but Apple M1 GPU performance must be measured rather than assumed.

The custom Godot fork adds `Environment.configure_sdfgi(enabled, cascades, cell_size, read_sky, feedback, energy)`. It validates all arguments, skips identical configurations and sends one RenderingServer update instead of several intermediate uploads. The GDScript runtime has a fallback for stock Godot APIs.

The native `ChunkedTerrain3D` creates RenderingServer RIDs instead of inheriting GeometryInstance3D. The `contribute_to_gi` property now sets `INSTANCE_FLAG_USE_BAKED_LIGHT` on both existing and newly streamed terrain chunks without rebuilding meshes or collision. The game explicitly enables this flag on its static heightfields; dynamic terrain should not use it.

Use a rebuilt Cgame engine to verify:

```sh
godot --headless --path game --script res://tests/run_graphics.gd
godot --headless --path game --script res://tests/run_all.gd
```

Engine regression checks: `tests/scene/test_sky.cpp` and `tests/scene/test_chunked_terrain_3d.cpp`. Game checks: `test_graphics_indirect_lighting.gd` and `test_terrain_sdfgi.gd`. Measure GPU p50/p95, VRAM/unified memory, leaks, GI convergence and camera motion on Apple M1. Source integration and regression definitions are not a substitute for passing compiled tests or device benchmarks.

SDFGI is not Lumen and does not instantly update moving GI occluders. See https://docs.godotengine.org/en/stable/tutorials/3d/global_illumination/using_sdfgi.html.


## Scene-aware SDFGI visibility (new)

Unreal Lumen uses a distance-field visibility representation; Unity HDRP's
Adaptive Probe Volumes support leak reduction. Godot's built-in SDFGI also
supports optional occlusion rays, but these can produce dark blotches outdoors
and add considerable GPU cost. Albion After therefore **never** enables those
rays in the open world.

The real playable clients sample the same existing authoritative dungeon
position used by software culling:

| World / tier | SDFGI | Occlusion rays | Sky GI | Normal/probe bias |
| --- | --- | --- | --- | --- |
| Outdoor, Ultra Forward+ | On | Off | On | 1.10 / 1.10 |
| Underground, Ultra Forward+ | On | On | Off | 0.95 / 0.95 |
| Performance / Balanced / High | Off | Off | Default | 1.10 / 1.10 |
| Compatibility / Mobile | Off | Off | Default | 1.10 / 1.10 |

Lower interior probe bias reduces indirect light leaking through nearby
geometry but can increase banding on slopes. Test shadow transitions and
increase it slightly only if real-device screenshots show streaks.

The custom engine provides
`Environment.configure_sdfgi_visibility(use_occlusion, read_sky_light,
normal_bias, probe_bias)`: an input-validated, idempotent, atomic
RenderingServer update instead of four intermediate submissions. Stock Godot
uses the standard Environment properties with change checks. No extra
volume, mesh rebuild, network message, scene shadow map or GI cascade is
allocated by this API. Additional occlusion rays **do cost GPU time** while
underground; Auto quality can disable them by leaving Ultra.

Implementation:
- `scene/resources/environment.cpp`: native visibility profile and binding
- `game/scripts/client/graphics_indirect_lighting.gd`: preset policy and fast path
- `game/scripts/client/graphics_quality.gd`: shared live update entry point
- `game/scripts/client/online_main.gd` and `client_main.gd`: actual interior transitions
- `tests/scene/test_sky.cpp`: engine regression
- `game/tests/test_graphics_indirect_lighting.gd`: game regressions

Rebuild the Cgame engine to verify the native method, then run the graphics
suite. Compare outdoor forests versus torchlit dungeons at a fixed camera,
resolution, exposure and quality. Measure GPU frame time, memory, occlusion
dark spots, bounce-light leaks and any GI convergence stutter. Source checks
alone cannot certify correctness on Apple M1.
