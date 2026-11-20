# High/Ultra native footprint decals

Inspired by Unity HDRP Decals and Godot Forward+ clustered projection:
players leave short-lived bootprints on rain-wet forest, swamp, beach and
plains soil, and on mountain snowpack (over 88 m elevation).

This is a render-only, pooled graphics subsystem, not permanent ground
geometry. A single 64x64 procedurally generated RGBA image per surface is
reused by every footprint; Ultra shares one shallow-normal texture.
Materials preserve existing scene PBR shading and receive native fade.

The projector pool is capped at 32. Each walking step needs approximately
0.83 m of real movement. Standing, mounts, water, tunnels, teleporting and
invalid weather create none. Renderers other than Forward+ and graphics
profiles below High never create projectors. Visible marks expire after
12 seconds, alpha changes no more than 4 Hz, and native distance fade
limits screen coverage to about 40 m.

Both multiplayer online_main and local client_main use the same code.
Godot's native Decal already provides the required engine functionality,
so no additional C++ renderer path or GPU pass is needed.

Tests in test_footprint_decals.gd are registered in both run_all.gd and
run_graphics.gd. Run the graphics checks with:
godot --headless --path game --script res://tests/run_graphics.gd

Visually validate actual shadowing, alpha and frame pacing on target GPUs.
