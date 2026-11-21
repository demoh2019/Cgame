# graphics_occlusion_quality.gd

> Screen-space contact shadows use one engine-native, half-resolution SSAO target.

`res://scripts/client/graphics_occlusion_quality.gd`

## Overview

Screen-space contact shadows use one engine-native, half-resolution
SSAO target. The quality profile changes only when graphics quality or
renderer backend changes; this is not an extra postprocess pass.

## Functions

### `settings`

```gdscript
static func settings(level: int, method: String) -> Dictionary
```

### `needs_apply`

```gdscript
static func needs_apply(previous: Dictionary, next: Dictionary) -> bool
```

### `apply`

```gdscript
static func apply(level: int, method: String) -> void
```

