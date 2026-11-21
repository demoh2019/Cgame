# graphics_sun_shafts.gd

> Screen-space volumetric sun shafts (god rays), the Unreal "Light Shafts" / CryEngine "Sun Shafts" technique: one fullscreen additive pass that marches toward...

`res://scripts/client/graphics_sun_shafts.gd`

## Overview

Screen-space volumetric sun shafts (god rays), the Unreal "Light Shafts" /
CryEngine "Sun Shafts" technique: one fullscreen additive pass that marches
towards the projected sun and streaks occluders through hazy air.
Forward+ High/Ultra only; Performance/Balanced/Compatibility pay nothing
(node hidden, no draw). The sun direction/colour is pushed only on change.

## Constants

- `const SHADER := preload("res://assets/shaders/sun_shafts.gdshader")`
- `const NODE_NAME := &"SunShafts"`

## Functions

### `settings`

```gdscript
static func settings(level: int, rendering_method: String) -> Dictionary
```

### `shaft_color`

```gdscript
static func shaft_color(light_color: Color, energy: float, sun_dir: Vector3) -> Color
```

Shaft tint: sun colour * energy, dimmed below the horizon (night/moon stays subtle).

### `apply`

```gdscript
static func apply(camera: Camera3D, sun_light: DirectionalLight3D, level: int, rendering_method: String) -> void
```

Idempotent: creates/updates/hides the pass under the active camera.

_2 private function(s) starting with `_` are not listed._
