# anim_lod.gd

> Animation update-rate LOD (Unreal URO / Unity culling mode) in GDScript: the fallback for engines without the native AnimationLODController.

`res://scripts/client/anim_lod.gd`

## Overview

Animation update-rate LOD (Unreal URO / Unity culling mode) in GDScript: the fallback for engines without the
native AnimationLODController. Registered AnimationPlayers run in manual mode and advance every 1st/2nd/4th frame
by distance, or not at all off-screen / far away, with skipped delta accumulated so animation time stays correct.

## Constants

- `const NEAR := 15.0`
- `const MID := 35.0`
- `const FAR := 70.0`
- `const MAX_ACCUMULATED := 0.5`
- `const NEAR_VIEW := 3.0 # Closer than this counts as visible (a point test would flicker at screen edges).`
- `const QUALITY_SCALE := [0.7, 1.0, 1.5, 2.5]` - Distance multiplier per GraphicsQuality level: Performance culls hardest, Ultra keeps full-rate animation farther.

## Functions

### `update_interval`

```gdscript
static func update_interval(distance: float, visible: bool, near: float = NEAR, mid: float = MID, far: float = FAR) -> int
```

Frame interval: 1 below near, 2 below mid, 4 below far, 0 (paused) beyond or when not visible.

### `distance_scale`

```gdscript
static func distance_scale(quality_level: int) -> float
```

### `tick`

```gdscript
static func tick(accumulated: float, delta: float, interval: int, frame: int, phase: int, max_accumulated: float = MAX_ACCUMULATED) -> Array
```

One frame for one animator. Returns [new_accumulator, advance_time]; advance_time < 0 means skip this frame.

### `register`

```gdscript
func register(animator: AnimationPlayer, model: Node3D) -> void
```

### `unregister`

```gdscript
func unregister(animator: AnimationPlayer) -> void
```

### `count`

```gdscript
func count() -> int
```

_4 private function(s) starting with `_` are not listed._
