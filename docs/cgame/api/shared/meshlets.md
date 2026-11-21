# meshlets.gd

> Meshlet (cluster) building and per-cluster culling, a CPU port of the ideas behind virtualized geometry (Nanite-style clusters).

`res://scripts/shared/meshlets.gd`

## Overview

```text
Meshlet (cluster) building and per-cluster culling, a CPU port of the ideas
behind virtualized geometry (Nanite-style clusters).

Credits / sources (ideas and formulas re-implemented from scratch, no code copied):
  - meshoptimizer by Arseny Kapoulkine, MIT license (meshlet building, normal-cone
    bounds and the cone culling test: dot(center - cam, axis) >= cutoff*|center - cam| + radius).
  - "A Deep Dive into Nanite Virtualized Geometry", Karis et al., SIGGRAPH 2021.
  - Bevy virtual geometry write-up (MIT / Apache-2.0), used for background only.

Conventions: triangle winding is Godot's (front faces are clockwise), so the
geometric normal that faces the viewer is (c - a) x (b - a). Meshlet dictionaries hold:
  indices        PackedInt32Array  triangle list, local indices into vertex_ids
  vertex_ids     PackedInt32Array  indices into the source vertex array
  bounds_center  Vector3, bounds_radius float (bounding sphere containing every vertex)
  cone_axis      Vector3, cone_cutoff float (normal cone; cutoff 1.0 = never cone-culled)
```

## Functions

### `build_meshlets`

```gdscript
static func build_meshlets(vertices: PackedVector3Array, indices: PackedInt32Array, max_vertices: int = 64, max_triangles: int = 124) -> Array
```

### `cone_cull`

```gdscript
static func cone_cull(meshlet: Dictionary, camera_pos: Vector3) -> bool
```

True when every triangle of the meshlet faces away from camera_pos (safe to skip).

### `frustum_cull`

```gdscript
static func frustum_cull(meshlet: Dictionary, planes: Array[Plane]) -> bool
```

True when the bounding sphere lies fully outside one plane. Planes use outward
normals (the Camera3D.get_frustum() convention): inside means distance_to() <= 0.

_2 private function(s) starting with `_` are not listed._
