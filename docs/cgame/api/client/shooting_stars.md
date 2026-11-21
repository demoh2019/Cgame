# shooting_stars.gd

> Occasional shooting stars on clear nights (Ghost of Tsushima / Firewatch skies).

`res://scripts/client/shooting_stars.gd`

## Overview

Occasional shooting stars on clear nights (Ghost of Tsushima / Firewatch skies).
A single additive streak far above the camera, animated every frame (the sky
shader refreshes on a slower cadence, so meteors live outside it).

## Constants

- `const MIN_GAP := 18.0`
- `const MAX_GAP := 55.0`
- `const LIFE := 0.7`

## Functions

### `allowed`

```gdscript
static func allowed(level: int, daylight: float, storm: float) -> bool
```

### `envelope`

```gdscript
static func envelope(t: float) -> float
```

Brightness envelope over a meteor's life (0..1): quick flare, longer fade.

### `update_view`

```gdscript
func update_view(daylight: float, storm: float, level: int, delta: float) -> void
```

_1 private function(s) starting with `_` are not listed._
