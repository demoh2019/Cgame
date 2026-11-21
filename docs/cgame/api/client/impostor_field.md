# impostor_field.gd

> Billboard/impostor LOD ring: past the real mesh's draw distance, the same placements continue as one MultiMesh of baked impostor quads, so distant hills keep...

`res://scripts/client/impostor_field.gd`

## Overview

Billboard/impostor LOD ring: past the real mesh's draw distance, the same
placements continue as one MultiMesh of baked impostor quads, so distant
hills keep their bushes and trees instead of popping to bare ground.

## Constants

- `const ImpostorBaker = preload("res://scripts/client/impostor_baker.gd")`
- `const META := &"aa_impostor_field"`

## Functions

### `configure`

```gdscript
static func configure(level: int) -> void
```

### `end_distance`

```gdscript
static func end_distance(mesh_range: float) -> float
```

### `add`

```gdscript
static func add(parent: Node3D, mesh: Mesh, transforms: Array[Transform3D], mesh_range: float, fade_margin: float = 8.0) -> MultiMeshInstance3D
```

