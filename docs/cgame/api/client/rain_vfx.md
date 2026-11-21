# rain_vfx.gd

> Camera-local rain rendering, shared by every multiplayer client.

`res://scripts/client/rain_vfx.gd`

## Overview

Camera-local rain rendering, shared by every multiplayer client.
GPU simulation on modern renderers, conservative CPU fallback on GL.
No gameplay collision, networking, resource generation or world writes.

## Constants

- `const GPU_COUNTS := [160, 460, 850, 1350]`
- `const CPU_COUNTS := [55, 110, 210, 320]`
- `const LIFE := 0.9`
- `const BOX := Vector3(26.0, 0.5, 26.0)`
- `const BOUNDS := AABB(Vector3(-27.0, -39.0, -27.0), Vector3(54.0, 43.0, 54.0))`

## Functions

### `use_gpu`

```gdscript
static func use_gpu(rendering_method: String) -> bool
```

### `budget`

```gdscript
static func budget(level: int, rendering_method: String) -> Dictionary
```

Bound resident particle storage to a quality tier, not to the per-frame
weather value. Modifying a GPU emitter's amount while active restarts it.

### `density`

```gdscript
static func density(intensity: float) -> float
```

Light drizzle yields few streaks, full storm uses the tier's entire cap.

### `create`

```gdscript
static func create(rendering_method: String) -> Node3D
```

### `apply_quality`

```gdscript
static func apply_quality(particles: Node3D, level: int) -> void
```

Called only when the active profile changes, not each weather frame.

### `update`

```gdscript
static func update(particles: Node3D, center: Vector3, intensity: float) -> void
```

Position follows the camera; existing particles stay in world coordinates,
so sprinting never drags all the streaks along with the player.

_2 private function(s) starting with `_` are not listed._
