# mesh_lod_preservation.gd

> Preserve Godot-imported mesh LODs while baking/resizing art into world-space meshes.

`res://scripts/client/mesh_lod_preservation.gd`

## Overview

Preserve Godot-imported mesh LODs while baking/resizing art into world-space meshes.

Godot generates per-surface LOD index buffers during glTF/FBX import, but
ArrayMesh.add_surface_from_arrays() does not inherit those buffers implicitly.
The public Mesh API exposes vertex arrays but not their LOD dictionary, so
read the surface's encoded index buffers through RenderingServer once, while
a static model is being cached. No per-frame CPU/GPU transfer is performed.

## Functions

### `copy_lods`

```gdscript
static func copy_lods(mesh: Mesh, surface: int, world_scale: float = 1.0) -> Dictionary
```

Returns a Dictionary[float, PackedInt32Array] for add_surface_from_arrays().
Edge-length thresholds scale with baked model size; indices themselves
remain valid because baking changes positions but not vertex order.

### `decode_indices`

```gdscript
static func decode_indices(encoded: PackedByteArray, stride: int, vertex_count: int) -> PackedInt32Array
```

Index data uses 16-bit storage for small meshes and 32-bit for large meshes.
Refuse malformed buffers instead of introducing out-of-range triangles.

