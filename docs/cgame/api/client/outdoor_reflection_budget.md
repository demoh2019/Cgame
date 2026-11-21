# outdoor_reflection_budget.gd

> Outdoor local reflection captures for shiny structures, wet stone and metal.

`res://scripts/client/outdoor_reflection_budget.gd`

## Overview

Outdoor local reflection captures for shiny structures, wet stone and metal.
One world-wide camera-local pool; chunks provide lightweight marker nodes,
never a ReflectionProbe each. Captures render once on location changes.
The sky remains the fallback outside probe influence and on low-end GPUs.

## Constants

- `const GROUP := "aa_outdoor_reflection_anchor"`
- `const CHECK_INTERVAL := 0.45`
- `const CAPTURE_COOLDOWN := 1.6`
- `const WEATHER_RECAPTURE_INTERVAL := 18.0`
- `const DAYLIGHT_RECAPTURE_DELTA := 0.17`
- `const STORM_RECAPTURE_DELTA := 0.26`
- `const SWITCH_HYSTERESIS := 5.0`
- `const SITE_KINDS := {`
- `const PRESETS := [`

## Documented variables

- `var atmosphere: Node3D` - Set by online_main when creating the one global reflection manager. Use the same smoothed atmospheric daylight/storm as the sky and PBR.

## Functions

### `configure`

```gdscript
static func configure(level: int) -> void
```

### `settings`

```gdscript
static func settings(level: int, method: String) -> Dictionary
```

### `belongs_to_chunk`

```gdscript
static func belongs_to_chunk(site_x: float, site_z: float, origin: Vector2, chunk_size: float) -> bool
```

Never spawn duplicates at site edges: only the chunk containing the site's
center owns its marker. The server and client use identical world cells.

### `choose`

```gdscript
static func choose(candidates: Array, count: int, radius: float, retained: Array = []) -> Array
```

Nearer captures win, but retain an assigned site until a different one
is at least 5m closer. No rapid recaptures while moving through a town.

### `weather_signature`

```gdscript
static func weather_signature(daylight: float, storm: float) -> Vector2
```

Pure scheduler: invalid or unavailable weather never forces cubemaps.

### `weather_changed`

```gdscript
static func weather_changed(captured: Vector2, current: Vector2) -> bool
```

### `make_probe`

```gdscript
static func make_probe(profile: Dictionary) -> ReflectionProbe
```

_3 private function(s) starting with `_` are not listed._
