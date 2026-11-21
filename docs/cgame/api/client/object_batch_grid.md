# object_batch_grid.gd

> Deterministic screen-space LOD / frustum-culling clusters for dense static world instances.

`res://scripts/client/object_batch_grid.gd`

## Overview

Deterministic screen-space LOD / frustum-culling clusters for dense static world instances.
Partition only repeated scenery. Server ids and transforms remain untouched.

## Constants

- `const MIN_INSTANCES := 12`
- `const SUBCELLS := 2`

## Functions

### `supports_partition`

```gdscript
static func supports_partition(kind: String) -> bool
```

### `key_for`

```gdscript
static func key_for(kind: String, world_position: Vector2, origin: Vector2, chunk_size: float, subcells: int = SUBCELLS) -> String
```

### `partition`

```gdscript
static func partition(by_kind: Dictionary, origin: Vector2, chunk_size: float, min_instances: int = MIN_INSTANCES, subcells: int = SUBCELLS) -> Dictionary
```

Output: stable batch id -> {kind, nodes}; the resource id on every node is preserved.

