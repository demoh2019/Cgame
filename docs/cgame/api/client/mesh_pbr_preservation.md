# mesh_pbr_preservation.gd

> Tangent-space preservation when fitting imported glTF/GLB meshes into world units.

`res://scripts/client/mesh_pbr_preservation.gd`

## Overview

Tangent-space preservation when fitting imported glTF/GLB meshes into world units.
A model-space transform can contain rotation, non-uniform scaling or a mirror.
Normals need an inverse-transpose; tangents need a forward transform followed
by re-orthogonalization. The tangent fourth component is bitangent handedness.
Compute this once on the CPU during cached mesh construction, never per frame.

## Constants

- `const StoneMicrodetail = preload("res://scripts/client/graphics_stone_microdetail.gd")`

## Functions

### `transform_frame`

```gdscript
static func transform_frame(arrays: Array, basis: Basis) -> bool
```

Return true when a valid tangent frame remains after transformation.
The caller owns the surface arrays; vertices are transformed separately.

### `material_for_bake`

```gdscript
static func material_for_bake(source: Material, tangent_frame_valid: bool, dungeon_style: bool = false, masonry_detail: bool = false) -> Material
```

Preserve normal/ORM/albedo maps and physically based material parameters.
Only disable normal mapping when the source geometry has no usable tangent frame.
Materials are duplicated, so changing the baked mesh never modifies imported art.

