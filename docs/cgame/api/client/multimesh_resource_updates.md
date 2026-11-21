# multimesh_resource_updates.gd

> (no header comment)

`res://scripts/client/multimesh_resource_updates.gd`

## Functions

### `apply`

```gdscript
static func apply(mm: MultiMesh, indices: PackedInt32Array, transforms: Array[Transform3D]) -> bool
```

Applies sparse native CGame MultiMesh updates, with a stock Godot fallback.
Validate all slots and transforms before touching any renderer state.

