# dungeon_torch_cookie.gd

> (no header comment)

`res://scripts/client/dungeon_torch_cookie.gd`

## Constants

- `const GraphicsAreaLights = preload("res://scripts/client/graphics_area_lights.gd")`
- `const WIDTH := 128`
- `const HEIGHT := 64`
- `const HIGH_SHADOW_DISTANCE := 27.0`
- `const ULTRA_SHADOW_DISTANCE := 38.0`

## Functions

### `intensity_at`

```gdscript
static func intensity_at(uv: Vector2) -> float
```

A world-independent equirectangular light mask. All longitude frequencies
are integers, so the 0/1 horizontal seam is perfectly periodic. At poles,
longitude dependence vanishes to prevent pinched radial artifacts.

### `texture`

```gdscript
static func texture() -> Texture2D
```

One 128x64 RGBA8 image, allocated once across ALL streamed room lights.
Avoid repeated texture creation when Auto changes graphics tiers.

### `projector_enabled`

```gdscript
static func projector_enabled(quality: int, method: String, casts_shadow: bool) -> bool
```

### `shadow_distance`

```gdscript
static func shadow_distance(quality: int) -> float
```

### `shadow_mode`

```gdscript
static func shadow_mode(quality: int) -> int
```

### `apply`

```gdscript
static func apply(light: OmniLight3D, quality: int, method: String, casts_shadow: bool) -> void
```

Applied only when the existing 0.13 s torch manager updates. Every
setter is idempotent: no repeated projector or shadow-atlas mutation.

