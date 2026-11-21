# trail_bike_visual.gd

> Lightweight procedural bike.

`res://scripts/client/trail_bike_visual.gd`

## Overview

Lightweight procedural bike. Visual only: movement, ownership and damage stay on GameServer.
No external asset pack or collision body is required.

## Constants

- `const WHEEL_RADIUS := 0.43`
- `const WHEEL_OFFSET := 0.72`

## Functions

### `build`

```gdscript
func build() -> void
```

### `set_riding`

```gdscript
func set_riding(riding: bool, speed: float = 0.0, delta: float = 0.0) -> void
```

### `set_panniers`

```gdscript
func set_panniers(enabled: bool) -> void
```

### `set_lamp`

```gdscript
func set_lamp(enabled: bool) -> void
```

### `wheel_count`

```gdscript
func wheel_count() -> int
```

_3 private function(s) starting with `_` are not listed._
