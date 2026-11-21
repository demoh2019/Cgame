# graphics_lighting.gd

> (no header comment)

`res://scripts/client/graphics_lighting.gd`

## Constants

- `const CinematicFog = preload("res://scripts/client/cinematic_fog.gd")`
- `const PracticalShadowCascades = preload("res://scripts/client/practical_shadow_cascades.gd")`

## Functions

### `settings`

```gdscript
static func settings(level: int, rendering_method: String) -> Dictionary
```

Forward+ is the only Godot 4 renderer with volumetric fog. Splitting the
main sun into four cascades improves nearby shadow precision, but costs
more draw work; reserve it for Ultra and stay at two splits on High.

### `apply`

```gdscript
static func apply(sun: DirectionalLight3D, environment: Environment, level: int, rendering_method: String) -> void
```

A single apply point keeps shadow settings consistent with the actual
backend, including after the user changes presets at runtime.

