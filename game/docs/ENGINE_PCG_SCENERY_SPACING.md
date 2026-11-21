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

This filter is **not** a Poisson-disk point generator or an Unreal PCG
graph replacement. It removes overlaps from an existing candidate set.

## Game integration

`SceneryBatches.thin_cosmetic_transforms` applies the filter to 3D
MultiMesh transforms in horizontal X/Z space. Streamed `ChunkView` nature
decorations thin *Bush* variants by 1.6 m and *Pebble* variants by 0.75 m.
Only visuals change. Interactive gatherables, authoritative resources,
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

The change reduces unnecessary overlapping cosmetic instance placements;
no claim of measured FPS improvement is made without hardware profiling.
