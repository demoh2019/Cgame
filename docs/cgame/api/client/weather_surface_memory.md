# weather_surface_memory.gd

> (no header comment)

`res://scripts/client/weather_surface_memory.gd`

## Constants

- `const ABSORPTION_PER_SECOND := 0.62` - Render-only ground moisture reservoir. Like HDRP rain/puddle material graphs, rain arrives quickly but surfaces dry slowly according to sun, wind and biome. No textures, per-chunk state, timers or game-server mechanics are allocated.
- `const DRYING_PER_SECOND := 0.008`
- `const MAX_STEP := 0.25`
- `const UPDATES_PER_SECOND := 5.0`

## Functions

### `next_wetness`

```gdscript
static func next_wetness(previous: float, rain: float, daylight: float, sun_height: float, wind: Vector2, biome: String, delta: float) -> float
```

### `active_rain`

```gdscript
static func active_rain(storm: float) -> float
```

GPU global updates are quantized to 5 Hz by Atmosphere, not per-pixel.

