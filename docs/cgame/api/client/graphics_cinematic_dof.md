# graphics_cinematic_dof.gd

> Thin-lens-inspired selective focus using Godot's *native* depth-of-field.

`res://scripts/client/graphics_cinematic_dof.gd`

## Overview

Thin-lens-inspired selective focus using Godot's *native* depth-of-field.
Far-only and Forward+ High/Ultra: player, nearby enemies and UI remain sharp.
One persistent CameraAttributesPractical owns both DOF and eye adaptation.
No duplicate fullscreen CanvasItem blur or camera-dependent material copies.

## Functions

### `settings`

```gdscript
static func settings(level: int, renderer: String, subject_distance: float, photo_mode: bool = false) -> Dictionary
```

Camera distance to the character is supplied by the active isometric orbit.
Keep the entire interactive vicinity in focus even while zooming or riding.

### `apply`

```gdscript
static func apply(world: WorldEnvironment, level: int, renderer: String, subject_distance: float = 22.0, photo_mode: bool = false) -> void
```

Coalesced native call on the fork. On stock Godot the same feature uses
ordinary setters, but only after a material change in distance/quality.

