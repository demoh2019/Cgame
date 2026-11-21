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

## Mixed 3D exclusion volumes (spheres + boxes)

The `PCGSpatialFilter3D.filter_indices_excluding_volumes()` method extends
the sphere-only PCG filter with **up to 128 inclusive axis-aligned boxes**:

```gdscript
var pcg := PCGSpatialFilter3D.new()
var selected := pcg.filter_indices_excluding_volumes(
    candidates, sphere_centers, sphere_radii, box_mins, box_maxs,
    2.1, 160)
```

- `box_mins` and `box_maxs` are matching `PackedVector3Array` bounds;
  each min component must be <= its corresponding max component.
  Degenerate point/plane/line boxes are valid and inclusive.
- All coordinates must be finite and within +/- 10,000,000. Box count
  cannot exceed 128; sphere count retains its independent 128 limit.
  Invalid boxes, spheres, candidate positions, spacing or budgets fail
  the entire request without partial output.
- Boxes are removed **before** spherical filtering and spatial-hash
  spacing, so excluded instances never reserve space. Original source
  indices are returned in deterministic order.
- Empty box arrays are exactly equivalent to the existing
  `filter_indices_excluding()`; empty sphere and box arrays reduce to
  `filter_indices()`. These APIs remain unchanged.
- The cost of checking boxes is bounded by O(N * boxes) on top of the
  existing spherical filtering and spatial-hash thinning. No physics,
  scene-tree mutations or GPU operations occur inside the native API.

The Days After prototype uses this to exclude decorative grass from
**elongated ruin walls and rectangular building/prop footprints**, while
keeping spherical exclusion around spawn and harvest points. The Cgame
native selector and stock Godot GDScript fallback are checked for parity
in the same headless gameplay smoke.

Reference: [Unreal Engine PCG Biome exclusions and volumes](https://dev.epicgames.com/documentation/en-us/unreal-engine/procedural-content-generation-pcg-biome-core-and-sample-plugins-overview-guide-in-unreal-engine).

## Stable density remap and probability selection (PCG Density)

`PCGDensitySelector` is a new reusable C++ engine class inspired by Unreal
PCG's Density Remap and point-filtering stages. It does **not** copy Unreal's
graph editor or perform scene mutation. Scripts can chain it before existing
3D exclusion-volume and point-spacing filters:

```gdscript
var policy := PCGDensitySelector.new()
var density := policy.remap_densities(
    PackedFloat32Array([0.0, 0.5, 1.0]), 0.0, 1.0, 0.2, 0.9)
var kept := policy.select_indices(density,
    PackedInt64Array([1001, 1002, 1003]), 27419, 4096)
```

`remap_densities(densities, input_min=0, input_max=1,
output_min=0, output_max=1, clamp_input=true)` transforms point density
linearly and clamps output to [0,1]; reversed output endpoints allow inverse
masks. `select_indices(densities, stable_ids, seed=0,
max_selected=4096)` uses a **32-bit avalanche hash of stable ID + seed**,
without consuming shared RNG state. The same ID's keep/discard decision
is independent of source traversal order, as long as output is not truncated
by the explicitly requested cap. Zero density always rejects, one always
accepts. This is a probabilistic selection, *not* Unreal's range-only
Density Filter node; it is a compact, reusable graph-like policy primitive.

Both functions validate their *entire* input before generating output. Densities
must be finite in [0,1], stable IDs in [0,2147483647], seed nonnegative,
input size at most 16384 and output cap 1–4096. Invalid requests return
empty arrays. Arrays are never mutated. Decisions remain deterministic
when the world is revisited; no cache or world-state reference is retained.

The playable Days After prototype applies a west-to-east density gradient
to its 625-candidate source grid, then preserves all existing sphere/box
exclusion and 2.1 m spacing checks. The game includes a GDScript fallback
with identical unsigned 32-bit hash semantics; smoke tests cover native/fallback
parity, bounds, stable IDs, repeat generation and resource-safe placement.

Reference: [Unreal Engine PCG node reference](https://dev.epicgames.com/documentation/en-us/unreal-engine/procedural-content-generation-framework-node-reference-in-unreal-engine).
