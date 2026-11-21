# hair_strands.gd

> Strand-based hair: guide-strand physics, interpolated render strands, capsule collision, LOD, culling and camera-facing ribbon mesh building.

`res://scripts/client/hair_strands.gd`

## Overview

```text
Strand-based hair: guide-strand physics, interpolated render strands, capsule collision,
LOD, culling and camera-facing ribbon mesh building.

Techniques (algorithms re-implemented from the papers/descriptions, no code copied):
- Dynamic Follow-The-Leader (DFTL): Matthias Mueller, Tae-Yong Kim, Nuttapong Chentanez,
  "Fast Simulation of Inextensible Hair and Fur", VRIPHYS 2012
  (https://matthias-research.github.io/pages/publications/FTLHairFur.pdf). Paper, no license
  implied; only the published idea is used.
- Global shape matching, local length constraints, guide -> render strand interpolation and
  capsule collision follow the concepts of AMD TressFX
  (https://github.com/GPUOpen-Effects/TressFX, Copyright (c) AMD, MIT license).
- Camera-facing ribbons expanded in the vertex shader (assets/shaders/hair_strand.gdshader).

Layout: guide g owns points [g*points_per_guide, (g+1)*points_per_guide); point 0 is the pinned
root. `rest` is in head space, `pos`/`prev` in world space (Verlet).
```

## Documented variables

- `var neighbors := PackedInt32Array()` - two nearest guides per guide, used for interpolation
- `var damping: float = 0.98` - per-frame (60 Hz) velocity retention
- `var stiffness: float = 0.08` - global shape matching, per-frame (60 Hz) pull toward the rest pose
- `var stiffness_root_bias: float = 0.5` - tip stiffness = stiffness * (1 - bias)
- `var ftl_damping: float = 0.9` - fraction of the constraint correction removed from velocity
- `var strand_spread: float = 0.012` - lateral jitter of interpolated strands (metres)

## Functions

### `grow_guides`

```gdscript
func grow_guides(root_points: PackedVector3Array, root_normals: PackedVector3Array, p_segments: int, length: float) -> void
```

Builds straight guides along the root normals (in head space).

### `add_capsule`

```gdscript
func add_capsule(a: Vector3, b: Vector3, r: float) -> void
```

### `clear_capsules`

```gdscript
func clear_capsules() -> void
```

### `reset`

```gdscript
func reset(head_transform: Transform3D) -> void
```

Snaps the whole hair to the rest pose under the given head transform (no velocity).

### `guide_points`

```gdscript
func guide_points(g: int) -> PackedVector3Array
```

### `step`

```gdscript
func step(dt: float, head_transform: Transform3D) -> void
```

### `render_strands`

```gdscript
func render_strands(per_guide: int, seed: int) -> Array
```

Interpolated render strands: per_guide strands per guide, blended from the guide and its two
nearest neighbours with seeded random weights and a lateral offset. Strand 0 of each guide is
the guide itself.

### `lod_strand_count`

```gdscript
func lod_strand_count(screen_coverage: float) -> int
```

Render strands per guide for a given screen coverage (0..1 of the viewport height-ish).
0 means too small to draw. Monotonic non-decreasing.

### `cull`

```gdscript
func cull(view_frustum_planes: Array[Plane], view_pos: Vector3) -> PackedInt32Array
```

Visible guide indices. `view_frustum_planes` use Godot's Camera3D.get_frustum() convention:
normals point outward, a point is inside when distance_to() <= 0 for every plane.

### `build_mesh`

```gdscript
func build_mesh(strands: Array, width: float) -> ArrayMesh
```

Ribbon mesh: every strand point becomes two vertices at the same position. Per vertex:
NORMAL = strand tangent, UV = (side 0/1, t root->tip), COLOR = (half width, per-strand random,
t, 1). The shader expands the ribbon toward the camera.

_2 private function(s) starting with `_` are not listed._
