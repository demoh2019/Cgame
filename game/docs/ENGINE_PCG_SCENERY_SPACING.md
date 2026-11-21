# Native PCG spatial point filtering for Albion After decor

Unreal Engine Procedural Content Generation (PCG) provides spatial point
sampling, filtering and biome workflows, including point-density controls.
Cgame adds a narrow, standalone native building block rather than copying the
entire PCG graph framework.

Documentation references:
- https://dev.epicgames.com/documentation/en-us/unreal-engine/procedural-content-generation-framework-in-unreal-engine
- https://dev.epicgames.com/documentation/en-us/unreal-engine/procedural-content-generation-framework-node-reference-in-unreal-engine

## Engine API

`PCGSpatialFilter2D.filter_indices(candidates: PackedVector2Array,
min_spacing: float, max_selected: int = 4096) -> PackedInt32Array`

- Greedy **input-order-stable** 2D spacing filter: accepts candidates whose
  distance to every prior accepted point is **at least** the spacing.
- Buckets accepted points into a native 2D hash grid; checks exactly nine
  neighboring cells, so typical lookup work is local, not all-pairs.
- Returns the original input indices, without reordering, touching scene
  objects, consuming RNG or changing source coordinates.
- Strict bounds: max 16,384 inputs, 4,096 selected indices, world coordinate
  magnitude <= 10,000,000, min spacing exactly 0 (no thinning) or 0.05–10,000.
  Invalid inputs return an empty array atomically.

## Variable-footprint self-pruning (new engine API)

`PCGSpatialFilter2D.filter_indices_scaled(candidates: PackedVector2Array,
scales: PackedFloat32Array, min_spacing: float, max_selected: int = 4096,
largest_first: bool = true) -> PackedInt32Array`

Inspired by Unreal PCG **Self Pruning → Large to Small**, the new method
accounts for each prop's scale. Point `i` and point `j` conflict when

`distance(i, j) < min_spacing * (scales[i] + scales[j]) / 2`.

- By default, larger candidates are evaluated first (input-index tie-break).
  Returns accepted indices sorted by their **original order**, so existing
  MultiMesh transform ordering and GPU buffer packing remain deterministic.
  Set `largest_first=false` for original-input-order greedy selection.
- Uniform scales of 1 match `filter_indices` exactly. A zero min-spacing
  retains the original prefix regardless of the priority flag.
- Native C++ uses a 2D grid checking 5×5 neighboring cells. Requiring finite
  scales within 0.5–2.0 bounds the search to those 25 buckets; candidate,
  selection, coordinate, and spacing limits stay unchanged.
- A missing or old native engine transparently falls back to matching
  GDScript logic. Invalid scale counts, NaN/Inf, out-of-range values or
  unsafe spacing reject the entire batch, not an accepted prefix.

This is a circular 2D footprint-spacing heuristic, **not** full mesh-bounds
intersections, GPU PCG execution or an implementation of Unreal's PCG graphs.

This filter is **not** a Poisson-disk point generator or an Unreal PCG
graph replacement. It removes overlaps from an existing candidate set.

## Game integration

`SceneryBatches.thin_cosmetic_transforms` preserves the original
fixed-spacing API. Existing `ChunkView` *Bush* variants continue using the
new 3D height-aware filter to preserve cliff/ledge spacing. Streamed *Pebble*
variants now use `SceneryBatches.thin_cosmetic_transforms_scaled` in horizontal
X/Z space: a 0.75 m base spacing is adjusted by each instance's randomized
uniform transform scale (clamped to 0.5–2.0). Large pebbles win over smaller
overlapping pebbles while output order remains stable. Only visuals change. Interactive gatherables, authoritative resources,
colliders, world geometry and infected spawn positions are never passed
through the filter.

The seeded RNG has already produced every candidate's full transform
*before* thinning. Thus later biome/decoration RNG draws are not shifted by
whether native Cgame or the stock Godot fallback is used.

On older engine binaries or stock Godot, a GDScript hash-grid fallback uses
the same greedy ordering and bounds as native C++. Headless native/fallback
random-input parity tests cover this contract.

## Validation

- Native doctests: `modules/procedural_scatter/tests/test_pcg_spatial_filter_2d.h`
- Game tests: `game/tests/test_pcg_scenery_spacing.gd`
- Headless runner: `game/tests/run_pcg_scenery_spacing.gd`
- CI: `.github/workflows/native-pcg-spatial-filter.yml`

The scale-aware policy can reduce overlapping visual placements without discarding large variants first;
no claim of measured FPS improvement is made without hardware profiling.
