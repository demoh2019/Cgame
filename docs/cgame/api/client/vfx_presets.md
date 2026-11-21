# vfx_presets.gd

> Gameplay effects authored as VFX-graph assets (vfx_graph.gd).

`res://scripts/client/vfx_presets.gd`

## Overview

Gameplay effects authored as VFX-graph assets (vfx_graph.gd). Each preset is
pure data: spawn/update modules plus event routing between emitters.

## Constants

- `const VfxGraphNode = preload("res://scripts/client/vfx_graph_node.gd")`
- `const SPARK_COUNTS := [0, 40, 70, 110]` - Particle counts per graphics level; Performance keeps the old burst only.

## Functions

### `lightning_sparks`

```gdscript
static func lightning_sparks(level: int) -> Dictionary
```

Lightning ground strike: white-hot sparks that bounce off the ground and
spawn short-lived embers on impact (collision event routing).

### `spawn`

```gdscript
static func spawn(parent: Node3D, asset: Dictionary, at: Vector3, seed_value: int) -> Node3D
```

Spawns a self-freeing effect node at a world position; null when disabled.

