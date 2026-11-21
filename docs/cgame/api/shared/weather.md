# weather.gd

> Deterministic weather shared by local preview, multiplayer and server.

`res://scripts/shared/weather.gd`

## Overview

Deterministic weather shared by local preview, multiplayer and server.
Weather is computed from world seed, 256m weather cells and server time.
No client-supplied weather value is ever accepted by the combat/survival rules.

## Constants

- `const WorldGen = preload("res://scripts/shared/world_gen.gd")`
- `const Defs = preload("res://scripts/shared/defs.gd")`
- `const WEATHER_CELL_METERS := 256.0`
- `const CHANGE_SECONDS := 240.0`
- `const COLD_START_C := 8.0`
- `const STORM_SIGHT_MULTIPLIER := 0.70 # Outdoors, rain makes visual tracking harder.`
- `const BIOME_TEMP_C := {`

## Functions

### `conditions`

```gdscript
static func conditions(world, x: float, z: float, server_seconds: float) -> Dictionary
```

### `wind_at`

```gdscript
static func wind_at(world, x: float, z: float, seconds: float) -> Vector2
```

Regional, seed-stable horizontal wind in metres per second. It changes with
the existing 256m weather cells and weather epochs, not with client FPS.
Smoke moves faster in storms, with no wind inside the protected hub.

### `protection`

```gdscript
static func protection(armor_id: String) -> float
```

Armor works as simple wind/rain insulation for the first survival slice.
The protection is derived from the equipped item on the authoritative server.

### `effective_severity`

```gdscript
static func effective_severity(weather: Dictionary, armor_id: String) -> float
```

### `sight_multiplier`

```gdscript
static func sight_multiplier(current: Dictionary) -> float
```

Server-owned storm data reduces sight only; non-visual senses stay unchanged.

