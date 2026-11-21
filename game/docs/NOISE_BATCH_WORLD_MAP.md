# Native batched noise sampling for Albion After

The Cgame engine extends `Noise` (including `FastNoiseLite`) with two CPU APIs:

- `get_noise_2dv_batch(points: PackedVector2Array) -> PackedFloat64Array`
- `get_noise_3dv_batch(points: PackedVector3Array) -> PackedFloat64Array`

Each returns one scalar-equivalent value for each input point, preserving input order, duplicates, 2D/3D seed settings, domain warp and fractal settings. Empty input gives an empty output. Nonfinite coordinates and inputs larger than 65536 points are rejected before sampling. These methods reduce script-to-native call overhead; they do not reduce the number of underlying noise samples or use GPU compute. No unmeasured speedup is claimed.

The **canonical** island chart in `game/scripts/client/world_map.gd` now prepares one row of coordinate/height samples, calls `WorldGen.biomes_at_points`, and paints the original biome palette. `WorldGen` uses native batch calls when present, otherwise the same scalar `Noise.get_noise_2d` implementation on stock Godot. The scalar `WorldGen.biome_at` remains authoritative for simulation. The chart no longer recomputes terrain height a second time per pixel just to classify its biome.

## Verification

Cgame native C++ tests: `godot --headless --test --test-case="*Point cloud sampling matches scalar noise*"`.

Albion After game tests, on both native Cgame and stock Godot: `godot --headless --path game --script res://tests/run_all.gd`. The new `test_noise_batch_sampling.gd` covers native/fallback noise parity and world biome parity.

For performance claims, benchmark generating the full 384×384 chart on the same machine with identical seed/settings, comparing before and after under both engines.
