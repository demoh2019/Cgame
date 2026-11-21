# footprint_decals.gd

> Bounded, pooled native Forward+ Decals for rain-soaked mud and high snow.

`res://scripts/client/footprint_decals.gd`

## Overview

Bounded, pooled native Forward+ Decals for rain-soaked mud and high snow.
One small shared image per surface; no server simulation or terrain edits.

## Constants

- `const MAX_MARKS := 32`
- `const HIGH_MARKS := 16`
- `const STEP_DISTANCE := 0.83`
- `const TELEPORT_DISTANCE := 5.0`
- `const DURATION := 12.0`
- `const FADE_INTERVAL := 0.25`
- `const TEX_SIZE := 64`

## Functions

### `surface_kind`

```gdscript
static func surface_kind(level: int, renderer: String, storm: float, biome: String, elevation: float, underground: bool, flooded: bool) -> String
```

### `max_marks`

```gdscript
static func max_marks(level: int) -> int
```

### `setup`

```gdscript
func setup(world) -> void
```

### `mask_at`

```gdscript
static func mask_at(uv: Vector2) -> float
```

### `valid_stride`

```gdscript
static func valid_stride(before: Vector3, after: Vector3, walking: bool) -> bool
```

### `clear_marks`

```gdscript
func clear_marks() -> void
```

### `update_track`

```gdscript
func update_track(at: Vector3, walking: bool, delta: float, storm: float, biome: String, level: int, renderer: String, underground: bool = false, flooded: bool = false) -> void
```

The caller owns terrain, weather and movement state. Only this local
presentation node changes, never the authoritative terrain or save game.

_4 private function(s) starting with `_` are not listed._
