# vfx_graph_node.gd

> Renders a VfxGraph system: one MultiMeshInstance3D (billboard quads) per emitter.

`res://scripts/client/vfx_graph_node.gd`

## Overview

Renders a VfxGraph system: one MultiMeshInstance3D (billboard quads) per emitter.
Particles are simulated in this node's local space. See vfx_graph.gd for the asset format.

## Constants

- `const VfxGraph = preload("res://scripts/client/vfx_graph.gd")`

## Signals

- `signal finished`

## Classes

- `class Renderer extends RefCounted:`

## Documented variables

- `@export var one_shot: bool = false` - Free the node once every emitter has finished and no particles remain.
- `@export var budget_particles: int = -1` - Max live particles across all emitters of this node (-1 = unlimited).

## Functions

### `setup`

```gdscript
func setup(asset: Dictionary, seed_value: int) -> void
```

### `step`

```gdscript
func step(delta: float) -> void
```

Advance the simulation and refresh the MultiMeshes (also used directly by tests).

### `particle_count`

```gdscript
func particle_count() -> int
```

### `is_finished`

```gdscript
func is_finished() -> bool
```

### `profile`

```gdscript
func profile() -> Dictionary
```

_2 private function(s) starting with `_` are not listed._
