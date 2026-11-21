# sun_shadow_atmosphere.gd

> (no header comment)

`res://scripts/client/sun_shadow_atmosphere.gd`

## Constants

- `const GraphicsLighting = preload("res://scripts/client/graphics_lighting.gd")` - Atmospheric shadow filtering in native Godot DirectionalLight3D. Only High/Ultra use variable penumbrae; no additional light or pass.

## Functions

### `profile`

```gdscript
static func profile(level: int, daylight: float, sun_height: float, storm: float) -> Dictionary
```

### `apply`

```gdscript
static func apply(sun: DirectionalLight3D, level: int, daylight: float, sun_height: float, storm: float) -> void
```

