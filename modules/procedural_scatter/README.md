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

## Yaw-oriented 3D exclusion volumes (OBB)

The native `PCGSpatialFilter3D.filter_indices_excluding_oriented_volumes()`
extends the existing sphere + AABB selector with **rotated** rectangular
footprints. This is useful for diagonal fences, ruined walls, long cabins,
fallen logs, and other rotated scenic objects where an inflated axis-aligned
exclusion would unnecessarily remove nearby vegetation.

```gdscript
var pcg := PCGSpatialFilter3D.new()
var selected := pcg.filter_indices_excluding_oriented_volumes(
    candidates, sphere_centers, sphere_radii, box_mins, box_maxs,
    PackedVector3Array([Vector3(13, 0.7, 13)]),
    PackedVector3Array([Vector3(5.4, 1.4, 1.4)]),
    PackedFloat64Array([deg_to_rad(35.0)]),
    2.1, 160)
```

- The new oriented-volume arrays have matching lengths up to **128**;
  world centers and nonnegative local half-extents define each volume.
  Yaw is in radians, limited to [-TAU, TAU], matching Godot's positive-Y
  `Basis(Vector3.UP, yaw)`. A candidate exactly on any box face is excluded.
- Oriented volumes are removed **before** existing AABB/sphere exclusion and
  the minimum-distance spatial hash. Returns stable original source indices,
  not indices in a temporary filtered array. Empty rotated arrays use the
  unchanged mixed-volume API.
- Precomputes each box's sine/cosine only once and checks points using
  inverse yaw in local XZ space. Bounded cost O(N × rotated boxes) in addition
  to the existing AABB/sphere work. No extra physics, GPU calls or RNG.
- Strict input validation, including candidates that would later be excluded:
  16,384 finite bounded positions, 128 rotated boxes, half-extents 0–10,000,
  4,096 selected indices, and existing sphere/AABB/spacing rules. Invalid
  requests reject the whole operation.
- `games/days_after/main.gd` now includes a genuinely rotated
  `DiagonalFence` collision/mesh. `foliage_scatter.gd` uses its matching
  oriented footprint in the native pipeline and the standalone GDScript
  fallback. The headless smoke checks the physical fence rotation, exclusion
  area, no spawned grass inside it, repeatability, and native/fallback parity.

This is a CPU preprocessing feature, **not GPU instance culling or Nanite**.
Actual frame-time performance requires profiling on representative scenes.
Reference: [Unreal PCG biome exclusions](https://dev.epicgames.com/documentation/en-us/unreal-engine/procedural-content-generation-pcg-biome-core-and-sample-plugins-reference-guide-in-unreal-engine).

## Seeded, stable-ID point density sampling

Inspired by Unreal Engine PCG point `$Density` and density filters,
Cgame now exposes a **native, deterministic** density operation:

```gdscript
var pcg := PCGSpatialFilter3D.new()
var ids := PackedInt32Array([10, 11, 12])
var densities := PackedFloat32Array([1.0, 0.0, 0.75])
var selected_indices := pcg.filter_indices_density(
    candidate_positions, densities, ids, 90421)
```

- `filter_indices_density(candidates, densities, stable_ids, seed,
  max_selected=4096)` uses a small 31-bit prime-modulus hash of each
  stable ID and the seed; **no global RNG**, allocation beyond the
  bounded working set, or scene traversal. Density zero always rejects,
  density one always accepts.
- A candidate's pass/fail decision depends on **stable ID and seed**,
  not array index or position. Reordering or reloading chunks does not
  change which stable IDs pass. Output contains original input indices
  in input order, with a final cap of 4096.
- Validation is all-or-nothing, including rejected/zero-density points:
  at most 16384 finite bounded positions, matching density and ID arrays,
  finite density values in [0,1], **unique** stable IDs in
  [0, 2147483646], seed in [0, 2147483646], output cap in [0,4096].
  Invalid data returns an empty array.
- Two multiply-add-modulus stages use integer intermediates below
  `2^53`, supporting exact C++/GDScript fallback parity. Hashes are
  deterministic distribution tools, not cryptographic identifiers.
- To preserve spatial coverage, **filter by density first**; then
  submit the surviving positions to `filter_indices_excluding_volumes()`
  for sphere/box exclusion and minimum spacing. Never select a capped
  first batch of 4096 if the next stage needs to consider more
  candidates — process bounded tiles independently instead.

### Days After biome example

The game uses stable IDs tied to 25×25 grid cells, with probabilities
from 0.13 on worn approaches to 0.94 in denser outskirts. The engine
samples points before mixed-volume rejection and spatial thinning.
Up to 160 collision-free grass blades render in one `MultiMesh` batch;
stock Godot can run an independent GDScript fallback. The smoke checks
the patchy density distribution, exclusion and spacing constraints,
regeneration, and native/fallback parity.

Upstream reference:
[Unreal PCG Framework Node Reference](https://dev.epicgames.com/documentation/en-us/unreal-engine/procedural-content-generation-framework-node-reference-in-unreal-engine).

## Native path-to-density mask (PCGPathFalloff3D)

The new `PCGPathFalloff3D` engine resource computes a deterministic
**horizontal polyline distance falloff** as a `PackedFloat32Array`:

```gdscript
var path_filter := PCGPathFalloff3D.new()
var trail_points := PackedVector3Array([
    Vector3(7, 0, 26), Vector3(0, 0, 3), Vector3(-7, 0, -26)])
var mask := path_filter.sample_factors(candidate_positions, trail_points, 1.8, 6.0)
for i in range(densities.size()):
    densities[i] *= mask[i]
# Then use PCGSpatialFilter3D.filter_indices_density() and
# filter_indices_excluding_volumes() to finish spawning vegetation.
```

- Points **within or on** the inner radius return factor 0 (no plants).
  Points **on or beyond** the outer radius return factor 1. Between them,
  cubic smoothstep yields a continuously graded density transition
  with zero slope at both edges.
- A polyline with 1–256 finite bounded points is evaluated in XZ.
  A one-point path behaves like a circle; repeated/zero-length
  segments work. Heights are validated but do not affect horizontal
  trail clearance.
- At most 16,384 candidate points; all coordinates in +/-10,000,000;
  radii must be ordered, finite and within 0–10,000. Invalid input
  rejects the whole batch without partial output. No RNG, scene
  mutation, physics call or renderer interaction.
- O(candidates × path_segments) bounded work; no temporary per-point
  scene objects or spatial index rebuild. For very long paths, split
  into spatially bounded tiles/chunks. No claim of faster frame times
  without engine profiling.
- Native unit tests cover smooth boundaries and derivatives, corners
  and endpoints, height invariance, degenerate/point paths, invalid
  arrays and maximum input size.

The **Days After** playable scene applies this mask to its stable
seeded grass density before sphere/AABB rejection and instance
spacing, producing a gently curved walkable route through the ruins.
The game also has a pure-GDScript implementation for older Godot
builds, with parity and gameplay smoke coverage.

Based on the *distance to spline* and *density remapping* concepts
in [Unreal Engine PCG framework node reference](https://dev.epicgames.com/documentation/en-us/unreal-engine/procedural-content-generation-framework-node-reference-in-unreal-engine).

## Unreal-style weighted procedural variant selection

Native `PCGWeightedVariantSelector` implements the selection policy
of Unreal's **PCG Mesh Selector Weighted** as an independent,
data-only operation, without reproducing the Unreal PCG graph editor.
It returns indices rather than loading mesh assets.

```gdscript
var selector := PCGWeightedVariantSelector.new()
var variants := selector.choose_variants(
    PackedInt64Array([101, 102, 103]),
    PackedFloat32Array([6.0, 3.0, 1.0]), 81419)
# One variant index (0, 1 or 2) per stable point ID.
```

- From 1–32 finite, nonnegative relative weights (each <=1,000,000),
  at least one must be strictly positive. Weights can be unnormalized.
  A zero-weight variant can never be chosen.
- Up to 16,384 stable point IDs in [0, 2147483647] and seed in the same
  range. The 32-bit avalanche hash guarantees a repeatable choice for
  every ID independently of traversal order and global RNG state.
  Duplicate IDs yield identical choices. Empty valid point input returns
  empty output; invalid inputs reject the entire batch without output.
- The selector is deterministic and CPU-only, but **does not perform
  spacing, exclusions, mesh creation, texture loading or GPU rendering**.
  Compose with existing native PCG filters for those behaviors.
- `games/days_after/pcg_weighted_variants.gd` implements the same
  unsigned 32-bit operations for stock Godot. Native C++ doctests and a
  headless gameplay runner check stable ID behavior, weight ratios,
  invalid input, zero weights and parity.

The Days After game uses weights 6:3:1 for green, autumn and dry blades,
tinting and scaling each instance within a **single MultiMesh**.
No per-frame point sampling or extra per-variant draw calls are introduced.
This is variation of *instance attributes* rather than allocation of three
separate mesh resources.

Reference: [Unreal PCG weighted mesh selectors](https://dev.epicgames.com/documentation/en-us/unreal-engine/procedural-content-generation-framework-node-reference-in-unreal-engine).
