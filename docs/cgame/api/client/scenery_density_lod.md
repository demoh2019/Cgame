# scenery_density_lod.gd

> Unreal foliage.DensityScale-style runtime geometry density for CLIENT decoration MultiMeshes only.

`res://scripts/client/scenery_density_lod.gd`

## Overview

Unreal foliage.DensityScale-style runtime geometry density for CLIENT
decoration MultiMeshes only. Native engine batches counts at once.
Existing MultiMesh buffers are immutable after creation: visible_instance_count
is the only GPU-facing property updated when quality/distance changes.

## Constants

- `const MAX_INSTANCES := 65536`
- `const MAX_CLUSTERS := 4096`
- `const MAX_DISTANCE := 10000000.0`
- `const NEAR_DISTANCE := 18.0`
- `const FAR_DISTANCE := 125.0`
- `const NEAR_DENSITY := [0.42, 0.68, 0.88, 1.0]`
- `const FAR_DENSITY := [0.20, 0.42, 0.70, 1.0]`
- `const DENSITY_DEADBAND := 2` - Time-coherent Unreal foliage density planning: a tiny count deadband prevents one/two plants popping on each 0.6-second camera update. A -1 previous value explicitly bypasses hysteresis after quality changes.
- `const LAST_QUALITY_META := "aa_density_lod_quality"`
- `const NEAR_PIXELS := 20.0` - Screen-size LOD compares the *projected size of a representative plant*, not the physical distance of its entire MultiMesh cluster. Perspective FOV, render resolution and orthographic zoom therefore influence geometry cost.
- `const FAR_PIXELS := 2.0`

## Functions

### `spread_indices`

```gdscript
static func spread_indices(count: int, prefer_native: bool = true) -> PackedInt32Array
```

A reversible bit-reversed order ensures that drawing a prefix of a cluster
does not display only the first anchors in its deterministic spawn sequence.

### `distribute_transforms`

```gdscript
static func distribute_transforms(transforms: Array[Transform3D], prefer_native: bool = true) -> Array[Transform3D]
```

### `plan_visible_counts`

```gdscript
static func plan_visible_counts(counts: PackedInt32Array, distances: PackedFloat32Array, quality: int, near_distance: float = NEAR_DISTANCE, far_distance: float = FAR_DISTANCE, prefer_native: bool = true) -> PackedInt32Array
```

### `plan_visible_counts_stable`

```gdscript
static func plan_visible_counts_stable(counts: PackedInt32Array, distances: PackedFloat32Array, previous_counts: PackedInt32Array, quality: int, deadband: int = DENSITY_DEADBAND, near_distance: float = NEAR_DISTANCE, far_distance: float = FAR_DISTANCE, prefer_native: bool = true) -> PackedInt32Array
```

### `plan_projected_visible_counts`

```gdscript
static func plan_projected_visible_counts(counts: PackedInt32Array, centers: PackedVector3Array, diameters: PackedFloat32Array, camera_position: Vector3, camera_forward: Vector3, focal_pixels: float, orthographic: bool, quality: int, near_pixels: float = NEAR_PIXELS, far_pixels: float = FAR_PIXELS, prefer_native: bool = true) -> PackedInt32Array
```

### `update_instances_projected`

```gdscript
static func update_instances_projected(instances: Array[MultiMeshInstance3D], camera: Camera3D, quality: int, prefer_native: bool = true) -> void
```

Compute the camera's vertical projection scale once, then send up to 4096
plants to native C++ in one batch. Old-engine/unsupported camera projection
paths retain the previous distance planner.

### `update_instances`

```gdscript
static func update_instances(instances: Array[MultiMeshInstance3D], camera_position: Vector3, quality: int, prefer_native: bool = true) -> void
```

Call once per chunk at a slow refresh cadence. Static authored mesh
visibility ranges/frustum culling still operate independently.

_7 private function(s) starting with `_` are not listed._
