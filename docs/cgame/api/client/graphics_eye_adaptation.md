# graphics_eye_adaptation.gd

> Native Godot camera exposure, limited to premium Forward+ renderers.

`res://scripts/client/graphics_eye_adaptation.gd`

## Overview

Native Godot camera exposure, limited to premium Forward+ renderers.
Uses one persistent CameraAttributesPractical on the shared WorldEnvironment.
It must not override the artist-driven ACES/day-night exposure curve.

## Functions

### `settings`

```gdscript
static func settings(level: int, method: String) -> Dictionary
```

### `apply`

```gdscript
static func apply(world: WorldEnvironment, level: int, method: String) -> void
```

