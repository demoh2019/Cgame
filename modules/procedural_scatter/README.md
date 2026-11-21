# Native procedural scatter filters (Cgame)

The native `PCGSpatialFilter3D` provides deterministic, data-only point spacing
and exclusion operations for biome decoration, dungeon dressing, resource-site
visuals and level generation. It is inspired by the PCG point-filtering and
exclusion-volume concepts in Unreal Engine, without using Unreal code.

## Runtime foliage density scalability (Unreal-inspired)

`PCGFoliageScalability3D` exposes two deterministic, data-only methods for
scalable instanced cosmetic vegetation:

- `spread_indices(count)` returns a bit-reversed index permutation, enabling
  the first visible subset of a MultiMesh to sample its **whole authored
  instance sequence** rather than showing only its earliest objects.
- `plan_visible_counts(counts, distances, quality, near_distance=18,
  far_distance=125)` processes up to 4096 instance clusters per native call.
  It returns a stable count for each cluster with smooth distance-based
  scaling and four quality levels. Performance uses near/far density 42%/20%,
  Balanced 68%/42%, High 88%/70%, and Ultra 100%/100%. Every nonempty
  visual group retains at least one instance; empty groups remain empty.
- All inputs are atomically validated: 0–65536 instances per cluster,
  0–4096 clusters, nonnegative finite distances ≤10,000,000 and valid
  distance windows. Invalid inputs return an empty packed result.
- This **does not implement Nanite or proxy-mesh HLOD**; it is an opt-in
  foliage-scalability API analogous to Unreal Engine's `foliage.DensityScale`.

In Albion After, `SceneryBatches.add(..., density_scalable=true)` creates a
permuted, immutable GPU MultiMesh **once**, then `SceneryDensityLod` updates
only `MultiMesh.visible_instance_count` every 0.6 s as needed. Flower,
grass, fern and petal decorations opt in; interactive loot, rocks, bushes,
terrain collisions and authoritative objects never do. Older/stock Godot
takes identical GDScript planning paths, with native-vs-fallback parity
tests and reversible Ultra recovery tests. No repeated mesh reuploads,
per-frame instance sorting, scene-node deletion or RNG draws.

Official inspiration: [Unreal foliage density scalability](https://dev.epicgames.com/documentation/en-us/unreal-engine/foliage-mode-in-unreal-engine).

## Temporal stability for runtime foliage density

The new native
`PCGFoliageScalability3D.plan_visible_counts_stable(counts, distances,
previous_counts, quality, deadband=2, near_distance=18, far_distance=125)`
reuses the deterministic base density planner but retains the old visible
count for a cluster when the new requested count differs by at most the
configured **0–8 instance deadband**. Once the difference is larger, the
new count is adopted immediately. Zero deadband reproduces the original
stateless policy. This reduces one/two-instance visibility thrashing as the
camera moves around the same distance while preserving the earlier stable
bit-reversed spatial instance prefix.

The engine does not store history: callers supply an index-aligned
`PackedInt32Array` of previous visible counts. A prior count of **-1**
explicitly means uninitialized or changed graphics tier; it bypasses the
deadband. This is crucial so Performance and Ultra changes immediately
apply the correct density, including restoring all instance transforms.
A previous count of zero cannot make a nonempty cosmetic cluster
permanently invisible. Invalid late previous counts, array length
mismatches, invalid distance/count/quality inputs or more than 4096
clusters reject the complete batch without partial changes.

**Albion After integration:** `SceneryDensityLod.update_instances()` is
called by real streamed `ChunkView` at the existing 0.6-second refresh
cadence. Only cosmetic flower/grass/fern/petal `MultiMeshInstance3D` nodes
opt in. They store their most recently applied *quality tier* in metadata
so changing graphics quality resets history; the current
`visible_instance_count` is reused only within that same tier. The
native API is feature detected; stock Godot/older Cgame binaries use
an equivalent deterministic GDScript fallback. No new mesh buffers,
per-frame loops, reuploads, collision work, loot/AI modification,
network state, or engine-side persistent allocations are introduced.

This combines [Unreal foliage density scalability](https://dev.epicgames.com/documentation/en-us/unreal-engine/foliage-mode-in-unreal-engine)
with the *temporal stability idea* of [Unreal Skeletal Mesh LOD Hysteresis](https://dev.epicgames.com/documentation/en-us/unreal-engine/skeletal-mesh-lods-in-unreal-engine);
it is **not** a claim that Unreal itself uses instance-count deadbands.

Run the `[PCGFoliageScalability3D]` native tests, the Albion After
`game/tests/run_pcg_scenery_spacing.gd` suite, and the static
`tests/scene/test_pcg_foliage_density_hysteresis_contract.py` contract.
A measurable FPS increase is not implied: this aims to reduce cosmetic
popping and redundant visibility-range updates.

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
ruins, resources and barricades, and draws up to 160 instances in bounded MultiMesh batches
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
Up to 160 collision-free grass blades render in at most three `MultiMesh` batches;
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
tinting and scaling each instance using mesh-specific GPU batches.
No per-frame point sampling or per-plant scene objects are introduced.
Each distinct mesh is grouped into one instancing component rather than
mixing incompatible geometry into a single MultiMesh.

Reference: [Unreal PCG weighted mesh selectors](https://dev.epicgames.com/documentation/en-us/unreal-engine/procedural-content-generation-framework-node-reference-in-unreal-engine).

## Native 3D polyline arc-length sampler

`PCGPolylineSampler3D.sample_positions(path_points, spacing,
max_samples=4096, fit_to_path=true)` is a data-only primitive inspired
by Unreal's **PCG Spline Sampler**. It supports prop placement on an
open straight-segment polyline with even **3D arc-length spacing**:

```gdscript
var sampler := PCGPolylineSampler3D.new()
var posts := sampler.sample_positions(route_waypoints, 1.35, 192, true)
# Use those positions to fill a MultiMesh, or instance scene objects.
```

- **Fit to path (default):** uses ceil(total_length / spacing) intervals
  and divides the full length equally, preserving *both endpoints*
  without a shortened final gap.
- **Fixed increment:** set fit_to_path to false for exact increments;
  the route ends only when it coincides with a spacing step.
- Degenerate/repeated vertices are safe. A single-point or zero-length
  path outputs one point, not a divide-by-zero. Corner spacing is
  measured *along* the route; fully 3D, including vertical segments.
- Accepts at most 256 finite waypoints within +/-10,000,000 per
  coordinate; spacing finite in [0.05,10,000], max_samples 1–4,096.
  Rejects invalid/oversized work atomically, including calculating the
  output count in double **before** integer conversion. No silent
  truncation or partial scene population.
- A single O(waypoints) segment-length pass followed by a monotonic
  O(samples + waypoints) walk; no physics, global RNG, scene traversals,
  or mesh/renderer allocations in native code.
- Returns a `PackedVector3Array` in route order. This polyline-only
  sampler does not calculate cubic Bézier tangents, pathfinding,
  terrain projection, or camera visibility; those are distinct tasks.

In `games/days_after/trail_markers.gd`, the live scene places
path-aligned ground stones at native sampled positions using **one
MultiMesh**, skips stones within building AABBs, and supplies the same
sampling algorithm in GDScript for stock Godot. Native unit tests and
game smoke assert both endpoints, spacing, limits, parity, and
regeneration.

Reference: [Unreal Engine PCG Spline Sampler settings](https://dev.epicgames.com/documentation/en-us/unreal-engine/BlueprintAPI/Utilities/Struct/BreakPCGSplineSamplerParams).

## PCG weighted mesh attribute batching

`PCGWeightedVariantSelector.partition_indices(variants, variant_count)`
adds the missing stage between the weighted selector and GPU instancing:

```gdscript
var selector := PCGWeightedVariantSelector.new()
var variants := selector.choose_variants(
    PackedInt64Array([101, 102, 103, 104]),
    PackedFloat32Array([6, 3, 1]), 81419)
var mesh_buckets := selector.partition_indices(variants, 3)
# Exactly three PackedInt32Array groups, including empty variants.
# Every original source point index occurs once in its selected group.
```

The native method is O(point count + variant count), supports at most
16,384 indices across 1–32 variants, and returns exactly one ordered
source-index group per variant (even if that geometry is absent).
Any invalid/negative/out-of-range index, invalid variant count or input
exceeding the limit returns an empty Array **without partially dropping
instances**. Valid empty inputs yield the requested number of empty groups.
It never touches meshes, materials, scene nodes, physics or renderer state,
so engine users can separately build their own per-mesh MultiMeshes.

`games/days_after/pcg_weighted_variants.gd` provides an independent
stock-Godot fallback. Existing `choose_variants()` remains unchanged.
The playable Days After scene takes each group's original source indices,
creates a distinct primitive mesh for each of the three variant types,
and updates only three reused GPU-instanced components. Neither physical
placement nor gameplay interactables are modified.

Unreal's [Instanced Static Mesh component](https://dev.epicgames.com/documentation/en-us/unreal-engine/instanced-static-mesh-component-in-unreal-engine)
uses the same grouping principle: identical geometry is instanced together.
Three different source meshes cost up to three draw batches here, rather than
the former one draw batch, but avoid per-plant draw calls and node overhead.
No unmeasured FPS gain is claimed.

## Tangent-aligned sampled PCG transforms

In addition to `sample_positions()`, the native
`PCGPolylineSampler3D.sample_transforms(path_points, spacing,
max_samples=4096, fit_to_path=true)` creates complete Godot
`Transform3D` frames for **every sampled point**:

```gdscript
var pcg := PCGPolylineSampler3D.new()
var frames: Array = pcg.sample_transforms(waypoints, 1.35, 192, true)
for i in range(frames.size()):
    multimesh.set_instance_transform(i, frames[i])
```

- The returned frame origins exactly match `sample_positions()`
  for the same inputs; the same sample-count cap, argument validation,
  interpolation, deterministic order and endpoint behavior apply.
  Invalid input returns an empty array, never partial geometry.
- Local **+Z** follows the full 3D tangent of the sampled path.
  A centered finite difference between adjacent samples softens
  orientation changes through corners; repeated points and exact
  180-degree reversals use deterministic fallback directions.
- The local X/Y/Z axes form an orthonormal, right-handed basis.
  A near-vertical tangent uses an alternate reference-up axis,
  avoiding NaNs and collapsed transforms. A completely degenerate
  route gets a stable +Z-forward identity orientation.
- No physics queries, node creation, global RNG mutations or GPU
  allocations occur in the native sampler. It emits up to 4096 frames
  with O(samples + waypoints) work; the caller handles instancing.
- This is **polyline tangent alignment**, not full Unreal PCG
  spline roll/twist interpolation or parallel-transport framing.
  Long curved meshes may need a dedicated twist-minimizing frame
  policy; for small prop instances these frames avoid manual yaw
  reconstruction in game scripts.

The live Days After `TrailMarkers` node consumes native frames
to orient individual instanced stones, retaining the existing AABB
clearance, uniform arc-length placement, one-MultiMesh batching and
full GDScript fallback. New native doctests cover corners,
vertical paths, U-turns, degenerate and single-point paths, output
bounds and 4096-frame caps. `trail_frames_smoke_test.gd` checks
the renderer instance transforms, frame orthogonality and native/
fallback parity.

Background: [Unreal PCG framework node reference](https://dev.epicgames.com/documentation/en-us/unreal-engine/procedural-content-generation-framework-node-reference-in-unreal-engine).
