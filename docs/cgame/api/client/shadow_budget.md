# shadow_budget.gd

> Per-chunk shadow caster LOD for the open world.

`res://scripts/client/shadow_budget.gd`

## Overview

Per-chunk shadow caster LOD for the open world.
A MultiMesh draws many objects in one pass, so limit participation in the sun's
shadow maps separately from its regular visibility. Simulation is untouched.
World-space bounds (rather than chunk centres) keep edge trees from losing shadows.

## Constants

- `const HYSTERESIS := 5.0`
- `const CAMERA_REFRESH_METERS := 1.5`
- `const CAMERA_REFRESH_SQUARED := CAMERA_REFRESH_METERS * CAMERA_REFRESH_METERS`
- `const SHADOW_CAPS := [0, 8, 16, 24]` - 128-slot native HLOD-style solar-shadow significance budget. Role preference: structures before trees before tiny bush shadows. All bounds are world-space, so large nearby groups survive culling.

## Functions

### `configure`

```gdscript
static func configure(profile: Dictionary) -> void
```

GraphicsQuality supplies the same profile on startup and whenever a preset changes.

### `revision`

```gdscript
static func revision() -> int
```

### `needs_refresh`

```gdscript
static func needs_refresh(last_eye: Vector2, last_revision: int, last_count: int, camera_eye: Vector2, caster_count: int) -> bool
```

Called once per streamed chunk every 0.5 s. When the eye is stationary,
skip all caster loops, transform updates and AABB distance calculations.
New chunks, scene changes and quality changes always refresh the state.

### `radius_for`

```gdscript
static func radius_for(role: String) -> float
```

### `distance_to_bounds_xz`

```gdscript
static func distance_to_bounds_xz(world_point: Vector3, bounds: AABB) -> float
```

Nearest horizontal point on the actual instance batch, not its centre. Works
when the camera moves inside a large group of trees as well as near tile edges.

### `should_cast`

```gdscript
static func should_cast(role: String, distance: float, currently_casting: bool) -> bool
```

Five-metre hysteresis prevents shadow maps being repeatedly invalidated at the
budget boundary. A zero radius disables the caster on Performance entirely.

### `cap_for_quality`

```gdscript
static func cap_for_quality(quality: int) -> int
```

### `role_index`

```gdscript
static func role_index(role: String) -> int
```

### `select_shadow_casters`

```gdscript
static func select_shadow_casters(bounds_min: PackedVector3Array, bounds_max: PackedVector3Array, roles: PackedByteArray, current: PackedByteArray, camera: Vector3, budget: int, prefer_native: bool = true) -> PackedInt32Array
```

Returns source indices ordered by visual significance; no scene mutations.
The pure GDScript fallback matches the native geometric and ranking rules.

_1 private function(s) starting with `_` are not listed._
