# contact_shadow_batch.gd

> Low-overhead grounding shadows for every streamed CharacterModel.

`res://scripts/client/contact_shadow_batch.gd`

## Overview

Low-overhead grounding shadows for every streamed CharacterModel.
One GPU MultiMesh draw, no per-NPC MeshInstances or shadow-map passes.
This is a purely visual fallback; movement/AI/collision stay unchanged.

## Constants

- `const GraphicsQuality = preload("res://scripts/client/graphics_quality.gd")`
- `const GROUP := "aa_grounded_characters"`
- `const UPDATE_PERIOD := 0.08 # ~12.5 CPU updates/s; GPU reuses transforms between updates.`
- `const MAX_INSTANCES := 192`
- `const MAX_RADIUS := 72.0`
- `const PRESETS := [`

## Functions

### `profile`

```gdscript
static func profile(level: int) -> Dictionary
```

### `select_actors`

```gdscript
static func select_actors(actors: Array[Dictionary], camera_position: Vector3, level: int, daylight: float, storm: float) -> Array[Dictionary]
```

A deterministic, testable visual priority queue. Actors beyond the draw
range never enter the GPU buffer; when crowded, the closest get priority.

### `setup`

```gdscript
func setup(atmosphere: Node = null) -> void
```

_2 private function(s) starting with `_` are not listed._
