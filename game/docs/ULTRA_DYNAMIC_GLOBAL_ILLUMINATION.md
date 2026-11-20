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
