# graphics_lens_rain.gd

> High-end virtual lens rain inspired by Unreal post materials and Unity HDRP.

`res://scripts/client/graphics_lens_rain.gd`

## Overview

High-end virtual lens rain inspired by Unreal post materials and Unity HDRP.
Integrates into the existing single post_grade.gdshader, never another
fullscreen layer. Clear weather and low-end hardware take the no-op path.

Dynamic gameplay comes from already-smoothed atmosphere weather, never
client-declared network inputs or new simulation state.

## Constants

- `const MAX_STRENGTH := 0.60`
- `const START_STORM := 0.38`

## Functions

### `strength_for`

```gdscript
static func strength_for(storm: float, level: int, method: String, underground: bool = false, sheltered: bool = false) -> float
```

### `screen_wind`

```gdscript
static func screen_wind(wind: Vector2) -> Vector2
```

A little horizontal drift from already cached 256m weather wind.
Wind values are allowed to be zero or corrupt without changing shaders.

### `apply`

```gdscript
static func apply(material: ShaderMaterial, storm: float, level: int, method: String, wind: Vector2, underground: bool = false, sheltered: bool = false) -> void
```

Called alongside GraphicsColorGrade at most five times per second, and
only in the online scene that already owns the fullscreen screen copy.

