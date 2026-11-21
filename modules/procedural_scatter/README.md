# Native procedural scatter filters (Cgame)

The native `PCGSpatialFilter3D` provides deterministic, data-only point spacing
and exclusion operations for biome decoration, dungeon dressing, resource-site
visuals and level generation. It is inspired by the PCG point-filtering and
exclusion-volume concepts in Unreal Engine, without using Unreal code.

## 3D exclusion zones

```gdscript
var filter := PCGSpatialFilter3D.new()
var points := PackedVector3Array([
    Vector3(0, 0, 0), Vector3(3, 0, 0), Vector3(5, 0, 0)])
var centers := PackedVector3Array([Vector3(0, 0, 0)])
var radii := PackedFloat64Array([2.0])
var indices := filter.filter_indices_excluding(
    points, centers, radii, 2.0, 128) # [1, 2]
```

- `filter_indices(candidates, min_spacing, max_selected=4096)` preserves the
  original spacing API.
- `filter_indices_excluding(candidates, exclusion_centers, exclusion_radii,
  min_spacing, max_selected=4096)` rejects all points **inside or on** any
  spherical exclusion zone **before** applying spacing. Excluded points never
  reserve a cell and therefore cannot create false holes in remaining points.
- Returns original source indices in stable candidate order. No RNG, scene
  mutation, physics query or engine-side object spawning occurs.
- Bounded input: 16,384 candidate points, 128 spheres, 4,096 selected points.
  Coordinates are finite and within +/-10,000,000; radii 0–10,000, and spacing
  is zero or 0.05–10,000. Invalid inputs fail the entire batch atomically,
  including malformed points that would otherwise have been excluded.
- Uses an O(N × zones) bounded prefilter and reuses the spatial-hash spacing
  algorithm. Allocation is O(N + zones); no global sort is performed.

## Game integration

`games/days_after/foliage_scatter.gd` generates candidate grass positions on
a shuffled deterministic grid, reserves spherical areas around player spawn,
ruins, resources and barricades, and draws up to 160 instances in one MultiMesh
batch. On Cgame, it calls the native API; on stock Godot, it follows the same
ordering in a GDScript fallback. The smoke test checks that no grass overlaps
reserved areas, spacing remains valid, and native/fallback output is identical.

The feature is purely cosmetic: it cannot despawn enemies, disable collisions,
interfere with loot, or change server-authoritative gameplay. Frame-time and
draw-call savings should be measured in a compiled game before claiming FPS
improvements.

Reference: https://dev.epicgames.com/documentation/en-us/unreal-engine/procedural-content-generation-pcg-biome-core-and-sample-plugins-reference-guide-in-unreal-engine
