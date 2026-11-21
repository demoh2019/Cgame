# graphics_color_grade.gd

> Cinematic time-of-day color separation for Albion After.

`res://scripts/client/graphics_color_grade.gd`

## Overview

Cinematic time-of-day color separation for Albion After.
Pure deterministic math: no textures, noise, extra fullscreen passes or
server state. The existing post material receives two vec3 uniforms at 5 Hz.

## Constants

- `const BASE_SHADOW := Vector3(-0.012, 0.0, 0.025)`
- `const BASE_HIGHLIGHT := Vector3(0.030, 0.015, -0.020)`

## Functions

### `palette`

```gdscript
static func palette(daylight: float, sun_height: float, storm: float, underground: bool = false) -> Dictionary
```

### `apply`

```gdscript
static func apply(material: ShaderMaterial, daylight: float, sun_height: float, storm: float, underground: bool = false) -> void
```

