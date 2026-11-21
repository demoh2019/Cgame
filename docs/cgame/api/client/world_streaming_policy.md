# world_streaming_policy.gd

> World Partition-style stream priority follows the actual movement mode.

`res://scripts/client/world_streaming_policy.gd`

## Overview

World Partition-style stream priority follows the actual movement mode.
This only reorders already-resident eligible cells; the engine remains
responsible for load/unload radius, queue hygiene and shared CPU budget.

## Constants

- `const WALK_LOOKAHEAD := 2.0`
- `const RIDING_LOOKAHEAD := 3.0`
- `const IDLE_VELOCITY_SQ := 0.16`
- `const VIEW_WEIGHTS := [0.35, 0.48, 0.66, 0.80]` - Visibility-weighted streaming source inspired by Unreal World Partition. View weighting affects ONLY scheduling, never player-centered residency. No camera or mesh work is performed in the native chunk generator.
- `const FAST_TURN_ANGLES := [60.0, 45.0, 35.0, 30.0]`

## Functions

### `lookahead_seconds`

```gdscript
static func lookahead_seconds(mounted: bool, velocity: Vector3) -> float
```

### `apply`

```gdscript
static func apply(streamer: WorldStreamer, mounted: bool, velocity: Vector3) -> void
```

Do not resend identical settings to the native streamer every render frame.
User preference, world radius and generation budget stay untouched.

### `view_weight`

```gdscript
static func view_weight(level: int) -> float
```

### `fast_turn_angle`

```gdscript
static func fast_turn_angle(level: int) -> float
```

### `ground_view`

```gdscript
static func ground_view(camera: Camera3D) -> Vector3
```

### `horizontal_cone_half_angle`

```gdscript
static func horizontal_cone_half_angle(fov: float, aspect: float, keep_height: bool) -> float
```

Convert the perspective camera into a conservative horizontal view cone.
The extra margin reduces visible pop-in around the screen edges.
Non-perspective cameras retain legacy heading-only streaming.

### `view_cone_half_angle`

```gdscript
static func view_cone_half_angle(camera: Camera3D) -> float
```

### `apply_view`

```gdscript
static func apply_view(streamer: WorldStreamer, camera: Camera3D, graphics_level: int) -> void
```

Run after Camera3D look_at(), so zoom/photo orbit uses the actual
rendered view instead of stale movement input. Native Cgame setters are
idempotent; do not touch loaded cells or resource allocations here.

### `waypoint_radius`

```gdscript
static func waypoint_radius(cell_size: float, mounted: bool) -> float
```

Nearby personal map markers become a bounded second streaming source.
Distant quest/map markers remain purely UI: they cannot load a second island
or bypass the player's authoritative chunk residency and CPU budgets.

### `waypoint_is_near`

```gdscript
static func waypoint_is_near(point: Vector2, player: Vector3, load_radius: float, cell_size: float) -> bool
```

### `plan_waypoint_route`

```gdscript
static func plan_waypoint_route(streamer: WorldStreamer, waypoint: Vector2, player: Vector3, blocked_cells: Array[Vector3i] = []) -> Array[Vector3i]
```

AStarGrid2D plans a 4-neighbor local path around optional blocked
streaming cells; the native WorldStreamer prioritizes its route but never
changes the player-centered resident set. A max 64-cell path and a 3-cell
detour margin keep this independent of global/untrusted map requests.

### `apply_waypoint_route`

```gdscript
static func apply_waypoint_route(streamer: WorldStreamer, waypoint: Vector2, player: Vector3, blocked_cells: Array[Vector3i] = []) -> void
```

Called from the existing private map-waypoint update, with an optional
game-owned hazard map. Never trusts remote players or creates new chunks.
Do not rerun AStar each render frame when both endpoint cells are stable.

### `apply_waypoint`

```gdscript
static func apply_waypoint(streamer: WorldStreamer, waypoint: Vector2, player: Vector3, mounted: bool) -> void
```

Called after focus_position updates, once per frame. Only the fork's
WorldStreamer implements this opt-in API; ordinary script code stays
compatible with projects that run on a binary without the extension.

### `format_focus_streaming_status`

```gdscript
static func format_focus_streaming_status(status: Dictionary) -> String
```

Read-only main streaming readiness for a compact client HUD indicator.
Older fork engines lack this native API; do not invent a percentage.
Game systems never use this cosmetic estimate as combat authority.

### `focus_loading_notice`

```gdscript
static func focus_loading_notice(streamer: WorldStreamer) -> String
```

