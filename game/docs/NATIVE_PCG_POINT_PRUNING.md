# Cgame PCG point self-pruning

## Engine API

`Geometry2D.prune_points_min_distance(points: PackedVector2Array, min_distance: float, max_kept: int = -1) -> PackedInt32Array`

The method takes candidate positions and returns **their original indices**, greedily rejecting a point if it is closer than `min_distance` to an earlier **kept** point. It keeps input order, respects a maximum count, and permits points at exactly the minimum distance. Unlike a Poisson-disk generator, it does not create new points or maximize coverage. Mesh extents/physical collisions are not considered.

- Finite nonnegative minimum distance; finite squared radius.
- Maximum 8,192 input points; `max_kept = -1` means unlimited, otherwise 0..8192.
- All coordinates must be finite, validated before selection.
- Zero radius preserves duplicates.
- Typical cases use an on-demand grid hash with nine neighboring cells; because a cell can hold two sufficiently distant points, each bucket contains a list of accepted indices.
- Extreme point-to-cell coordinate ratios safely fall back to exact direct scanning to avoid integer overflow.
- No persistent engine object, no GPU resources, no mutable scene state and no network authority.

Design comparison: [Unreal Engine PCG Self Pruning](https://dev.epicgames.com/documentation/unreal-engine/procedural-content-generation-framework-node-reference-in-unreal-engine?lang=en-US) filters overlapping generated point data. Cgame adds a simple deterministic 2D numerical primitive, not Unreal's graph scheduler or mesh-surface Poisson sampler.

## Albion After integration

The real `game/scripts/client/ground_plants.gd` tile generator now creates extra seeded candidates for **boulders, stones and larger shrubs**, then prunes their 2D origins in one native call before biome/height checks and MultiMesh instance creation. Each species has a different separation threshold (2.4m boulders, 1.3m shrubs, 0.65m stones). Jittered dense grass cards and clustered flowers preserve their earlier scatter pattern. Selection is per tile/species, so separation across separate tile boundaries or across unrelated species is **not** guaranteed.

`game/scripts/client/point_spacing.gd` provides a matching GDScript scalar fallback for stock Godot. The generator remains client-only; world terrain, server gameplay and network/save formats are unchanged.

## Tests and validation

- `tests/core/math/test_geometry_2d.cpp`: stable greedy selection, equal-distance boundaries, duplicates, max-kept, same-cell multiple points, extreme coordinate fallback and invalid inputs.
- `game/tests/test_point_spacing.gd`: native/scalar parity, seeded sample reproducibility and minimum-spacing proof across all generated pairs.
- Registered in `game/tests/run_all.gd`, alongside existing grass/foliage tests.

Local build and headless Godot tests are still needed; do not claim a measured performance improvement without benchmarking.
