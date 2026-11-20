# Weather-coupled GPU wind for foliage

Trees and procedural grass now bend according to the deterministic regional
`Weather.wind_at` field used for smoke, not unrelated shader oscillations.
The online and offline client sample weather at **4 Hz** and the shared
Atmosphere smooths directional changes. A single shader global
`aa_vegetation_wind` (vec3: x/z direction and 0–1 strength) is uploaded
at **10 Hz**. Both materials reuse their original GPU shaders and MultiMesh
draws; no per-tree script, network message or per-chunk mesh rebuild is added.

Storms bend both tree crowns and grass in the same direction; sheltered
areas and underground scenes calm the vegetation. Animation still fades
by distance and respects the existing graphic presets.

Inspired by modern foliage pipelines that combine GPU instancing and shared
wind fields, rather than running separate animations for each object.
Does not implement Nanite, procedural bend bones or GPU occlusion.

Tests: `res://tests/test_vegetation_wind.gd`, included in the suite.
Run from the repository root:
`godot --headless --path game --script res://tests/run_all.gd`.
GPU profiling and screenshots are still required for performance claims.
