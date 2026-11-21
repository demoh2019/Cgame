# heightfield_gradients.gd

> Read-only row-major heightfield gradients for cartographic hillshade and procedural terrain slope masks.

`res://scripts/client/heightfield_gradients.gd`

## Overview

Read-only row-major heightfield gradients for cartographic hillshade and
procedural terrain slope masks. The fork provides a native batch; stock
Godot uses the same clamped-edge central differences in GDScript.

## Functions

### `compute`

```gdscript
static func compute(heights: PackedFloat32Array, size: Vector2i, spacing: float, force_scalar: bool = false) -> PackedVector2Array
```

### `surface_normal`

```gdscript
static func surface_normal(gradient: Vector2) -> Vector3
```

