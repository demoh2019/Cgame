# cluster_lod.gd

> Cluster DAG LOD hierarchy and screen-space-error cut selection (Nanite-style, CPU).

`res://scripts/shared/cluster_lod.gd`

## Overview

```text
Cluster DAG LOD hierarchy and screen-space-error cut selection (Nanite-style, CPU).

Credits / sources (concepts re-implemented from scratch, no code copied):
  - "A Deep Dive into Nanite Virtualized Geometry", Karis et al., SIGGRAPH 2021
    (cluster groups, locked group borders, parent-error cut rule).
  - meshoptimizer by Arseny Kapoulkine, MIT license (clusterization and quadric
    edge-collapse simplification ideas, locked vertices).
  - Garland & Heckbert, "Surface Simplification Using Quadric Error Metrics" (1997).
  - Bevy virtual geometry write-up (MIT / Apache-2.0), background only.

Vertices must be welded (shared by index) so neighbouring clusters share ids.
Hierarchy dictionary: vertices, clusters (Array of Dictionary), levels, roots.
Cluster: indices (global triangle list), vertex_ids, center/radius (geometry sphere),
cone_axis/cone_cutoff, level, error + lod_center/lod_radius (own LOD sphere, shared by
the whole group that produced it), parent_error/parent_center/parent_radius (INF for
roots), children (cluster ids of the group this cluster was simplified from).
```

## Constants

- `const Meshlets = preload("res://scripts/shared/meshlets.gd")`
- `const GROUP_SIZE := 4`

## Functions

### `build_hierarchy`

```gdscript
static func build_hierarchy(vertices: PackedVector3Array, indices: PackedInt32Array, levels: int = 4) -> Dictionary
```

### `select_cut`

```gdscript
static func select_cut(hierarchy: Dictionary, camera_pos: Vector3, fov_y: float, screen_height: float, error_pixels: float = 1.0) -> PackedInt32Array
```

Clusters whose own projected error <= error_pixels < parent's projected error.
Own and parent LOD values are shared across a group, so the cut has no cracks/overlap.

### `triangle_count`

```gdscript
static func triangle_count(hierarchy: Dictionary, cut: PackedInt32Array) -> int
```

_9 private function(s) starting with `_` are not listed._
