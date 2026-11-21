# character_rain_gear.gd

> Weather-responsive outfit materials without a new shader, draw pass, or duplicated PBR textures.

`res://scripts/client/character_rain_gear.gd`

## Overview

Weather-responsive outfit materials without a new shader, draw pass, or
duplicated PBR textures. All animated characters share the same per-source
material variants. Godot's StandardMaterial3D preserves source maps/tangents.
Only real imported opaque clothing/gear is registered by CharacterModel.

## Constants

- `const STEPS := 4`
- `const QUALITY_STRENGTH := [0.0, 0.35, 0.72, 1.0]`

## Functions

### `supports`

```gdscript
static func supports(source: StandardMaterial3D) -> bool
```

### `step_for`

```gdscript
static func step_for(wetness: float, quality: int, method: String) -> int
```

Only apply expensive clearcoat in the Forward+ High/Ultra renderers.
Compatibility still darkens fabric slightly on wet days at one cheap tier.

### `variant`

```gdscript
static func variant(source: StandardMaterial3D, step: int) -> StandardMaterial3D
```

### `clear_cache`

```gdscript
static func clear_cache() -> void
```

