# graphics_white_balance.gd

> Time-of-day white balance through the engine fork's native Environment.lens_white_temperature/tint (UE5 White Temp/Tint): warm golden hour, cool blue moonlig...

`res://scripts/client/graphics_white_balance.gd`

## Overview

Time-of-day white balance through the engine fork's native
Environment.lens_white_temperature/tint (UE5 White Temp/Tint): warm golden
hour, cool blue moonlight, slightly green-grey storm light. Pushed only when
the value moves (>0.01), so ordinary frames make no RenderingServer call.

## Functions

### `target`

```gdscript
static func target(daylight: float, sun_height: float, storm: float) -> Vector2
```

Returns Vector2(temperature, tint), both -1..1.

### `apply`

```gdscript
static func apply(env: Environment, daylight: float, sun_height: float, storm: float, neutral: bool = false) -> void
```

