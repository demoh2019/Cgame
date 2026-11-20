# Geometry-error terrain LOD (Cgame engine + Albion After)

Cgame's custom ChunkedTerrain3D already supports skirts, hysteresis,
FOV-aware distance LOD and optional High/Ultra vertex geomorphing.
This change prevents aggressive simplification of rugged ridges that
would be acceptable on flat ground but visibly distort mountain shapes.

The engine caches the maximum difference between each coarse LOD's
triangle surface and the source heightmap, once per chunk rebuild.
The camera update projects the error to approximate screen pixels.
Detailed terrain remains active when the expected error is too large;
otherwise the original low-cost distance LOD is used. A protected ridge
is not allowed to morph toward the rejected coarse surface.

The optional ChunkedTerrain3D.max_lod_pixel_error property defaults to 0.
The game selects 0 px for Performance/Balanced, 3 px for High, and 1.5 px
for Ultra. Presets affect both active and newly streamed terrain.
The bound has a fixed eight-value CPU cache per chunk and adds no GPU
textures, new meshes, new passes or gameplay collision changes.

Technique: adapting terrain geometric-error LOD used in large landscape
renderers, rather than claiming Unreal Engine Nanite implementation.
Projection is approximate; actual captures and GPU profiling on real
hardware are still required.

Tests: tests/scene/test_heightmap_terrain_geometry.cpp,
tests/scene/test_chunked_terrain_3d.cpp, and
game/tests/test_terrain_geomorph.gd.
Game command: godot --headless --path game --script res://tests/run_all.gd
