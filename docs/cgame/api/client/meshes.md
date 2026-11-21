# meshes.gd

> Low-poly meshes built in code, so the game needs no imported art.

`res://scripts/client/meshes.gd`

## Overview

Low-poly meshes built in code, so the game needs no imported art. Each is a single vertex-coloured
surface, which lets a MultiMesh draw thousands of them in one call.

## Functions

### `get_mesh`

```gdscript
static func get_mesh(name: String) -> Mesh
```

### `material`

```gdscript
static func material() -> StandardMaterial3D
```

_14 private function(s) starting with `_` are not listed._
