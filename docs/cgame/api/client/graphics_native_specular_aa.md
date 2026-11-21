# graphics_native_specular_aa.gd

> Godot's built-in screen-space roughness limiter controls the unmodified imported glTF/PBR assets, complementing the game's terrain/foliage shader AA.

`res://scripts/client/graphics_native_specular_aa.gd`

## Overview

Godot's built-in screen-space roughness limiter controls the unmodified
imported glTF/PBR assets, complementing the game's terrain/foliage shader AA.
Unlike a full-screen image blur it filters glancing highlights at the
material stage. No additional samplers, textures, or framebuffer passes.
RenderingServer setting is process-global: cache actual applied plan.

## Functions

### `plan`

```gdscript
static func plan(level: int, method: String) -> Dictionary
```

### `needs_apply`

```gdscript
static func needs_apply(previous: Dictionary, next: Dictionary) -> bool
```

### `apply`

```gdscript
static func apply(level: int, method: String) -> void
```

