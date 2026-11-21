# graphics_foveated_shading.gd

> Variable Rate Shading / foveated rendering (UE5 VRS, Unity foveation, Metal rasterization rate maps).

`res://scripts/client/graphics_foveated_shading.gd`

## Overview

Variable Rate Shading / foveated rendering (UE5 VRS, Unity foveation,
Metal rasterization rate maps). The top-down camera keeps the player at
screen center, so edges are shaded at coarser rates on low presets.
Unsupported GPUs ignore the texture; High/Ultra always shade full rate.

## Constants

- `const RATE_1X1 := Color8(0, 0, 0)`
- `const RATE_2X2 := Color8(85, 85, 0)`
- `const RATE_4X4 := Color8(170, 170, 0)`
- `const RATE_2X1 := Color8(85, 0, 0)`
- `const TILE := 16 # Matches the common 16px shading-rate tile; Godot rescales anyway.`

## Functions

### `settings`

```gdscript
static func settings(level: int, rendering_method: String) -> Dictionary
```

### `build_map`

```gdscript
static func build_map(size: Vector2i, inner: float, outer: float) -> Image
```

Elliptical rate map: full rate around the player, 2x2 ring, 4x4 corners.

### `apply`

```gdscript
static func apply(viewport: Viewport, level: int, rendering_method: String) -> bool
```

