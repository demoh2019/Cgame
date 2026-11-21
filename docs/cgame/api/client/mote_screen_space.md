# mote_screen_space.gd

> Fixed-pixel atmospheric particle footprints.

`res://scripts/client/mote_screen_space.gd`

## Overview

Fixed-pixel atmospheric particle footprints. Perspective world size scales
with camera depth; orthographic size is constant. Pure fallback for stock
Godot, whose Camera3D has no native world-size projection helper.

Unreal TSR's thin-feature discussion motivates avoiding huge subpixel-to-
multpixel shifts; this does NOT implement temporal reconstruction or TSR.

## Constants

- `const MIN_WORLD_DIAMETER := 0.012`
- `const MAX_WORLD_DIAMETER := 0.40`

## Functions

### `target_pixels`

```gdscript
static func target_pixels(level: int, render_scale: float = 1.0) -> float
```

### `safe_diameter`

```gdscript
static func safe_diameter(world_size: float) -> float
```

### `fallback_world_diameter`

```gdscript
static func fallback_world_diameter(target: float, viewport: Vector2, fov_deg: float, orthogonal_size: float, keep_width: bool, orthogonal: bool, depth: float) -> float
```

Exact for perspective FOV and orthogonal camera with either keep-aspect
mode. For an asymmetric frustum stock Godot uses this conservative estimate.

