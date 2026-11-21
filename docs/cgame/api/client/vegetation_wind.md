# vegetation_wind.gd

> (no header comment)

`res://scripts/client/vegetation_wind.gd`

## Constants

- `const MAX_SPEED := 1.5` - Regional weather becomes one GPU wind vector for all instanced vegetation. xy = direction, z = strength 0..1. No changes to authoritative simulation.
- `const RESPONSE := 4.0`

## Documented variables

- `static var current := Vector3.ZERO` - Latest published wind for CPU-side effects (lanterns, smoke). Reading the shader global back is editor-only and returns null in exported or running games.

## Functions

### `target`

```gdscript
static func target(wind: Vector2) -> Vector3
```

### `smooth`

```gdscript
static func smooth(previous: Vector3, next: Vector3, delta: float) -> Vector3
```

