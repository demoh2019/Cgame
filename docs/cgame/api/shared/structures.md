# structures.gd

> Rules for a bounded, session-local defensive structure in the authoritative world.

`res://scripts/shared/structures.gd`

## Overview

Rules for a bounded, session-local defensive structure in the authoritative world.
2D circular obstacle collision is shared by survivors and infected.
Visual/physics bodies may be created by clients but never decide durability.

## Constants

- `const COST := {"wood_1": 4, "stone_1": 2}`
- `const REPAIR_COST := {"wood_1": 1}`
- `const SALVAGE_GOOD := {"wood_1": 2, "stone_1": 1}`
- `const SALVAGE_DAMAGED := {"wood_1": 1}`
- `const DISMANTLE_RANGE := 3.0`
- `const MAX_HEALTH := 120.0`
- `const MAX_TIER := 4`
- `const MAX_HEALTH_BY_TIER := [0.0, 120.0, 240.0, 400.0, 600.0]`
- `const DAMAGE_FACTOR_BY_TIER := [0.0, 1.0, 0.82, 0.66, 0.5]`
- `const REPAIR_AMOUNT_BY_TIER := [0.0, 40.0, 60.0, 85.0, 110.0]`
- `const UPGRADE_COST_BY_TIER := {`
- `const REPAIR_COST_BY_TIER := {`
- `const UPGRADE_RANGE := 3.0`
- `const REPAIR_HEALTH := 40.0`
- `const RADIUS := 0.85`
- `const BUILD_RANGE := 4.0`
- `const MIN_BUILD_DISTANCE := 1.7`
- `const REPAIR_RANGE := 3.0`
- `const MIN_HUB_DISTANCE := 50.0`
- `const MAX_PER_OWNER := 12`
- `const MAX_GLOBAL := 300`
- `const MIN_SLOPE_NORMAL_Y := 0.78`
- `const ZOMBIE_REACH := 1.75`
- `const ROTATION_STEP := PI / 4.0 # Walls turn in eighths of a circle, so lines and corners meet.`
- `const UPKEEP_SECONDS := 6.0 * 3600.0`
- `const UPKEEP_RANGE := 15.0`
- `const DECAY_SECONDS := 2.0 * 3600.0`

## Functions

### `tier_of`

```gdscript
static func tier_of(data: Dictionary) -> int
```

### `valid_tier`

```gdscript
static func valid_tier(tier: int) -> bool
```

### `max_health`

```gdscript
static func max_health(tier: int) -> float
```

### `color_for_tier`

```gdscript
static func color_for_tier(tier: int) -> Color
```

### `upgrade_cost`

```gdscript
static func upgrade_cost(tier: int) -> Dictionary
```

### `repair_cost`

```gdscript
static func repair_cost(tier: int) -> Dictionary
```

### `repair_amount`

```gdscript
static func repair_amount(tier: int) -> float
```

### `damage_factor`

```gdscript
static func damage_factor(tier: int) -> float
```

### `can_manage`

```gdscript
static func can_manage(data: Dictionary, peer_id: int, user_id: String) -> bool
```

Authenticated owners keep management rights after reconnecting with a new peer ID.
Guest structures intentionally remain session/peer owned until accounts exist.

### `salvage_for_health`

```gdscript
static func salvage_for_health(hp: float, tier: int = 1) -> Dictionary
```

### `within_range`

```gdscript
static func within_range(a: Vector2, b: Vector2, limit: float) -> bool
```

### `public_state`

```gdscript
static func public_state(data: Dictionary) -> Dictionary
```

### `placement_reason`

```gdscript
static func placement_reason(world, point: Vector2, from: Vector2) -> String
```

Where a wall may stand, judged from the builder's position: "" when it may, else the reason. The server checks this and
more (other walls, people, materials); the client uses it to colour the placement ghost.

### `snap_yaw`

```gdscript
static func snap_yaw(yaw: float) -> float
```

Facing snapped to the rotation step; anything not a finite number faces north.

### `decay_per_second`

```gdscript
static func decay_per_second(tier: int) -> float
```

