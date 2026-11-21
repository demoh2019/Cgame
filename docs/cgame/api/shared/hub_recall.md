# hub_recall.gd

> (no header comment)

`res://scripts/shared/hub_recall.gd`

## Constants

- `const ZoneRisk = preload("res://scripts/shared/zone_risk.gd")` - Paid non-full-loot return to a safe settlement. All decisions are server-side.
- `const Movement = preload("res://scripts/shared/movement.gd")`
- `const ITEM_ID := "return_charm"`
- `const CHANNEL_SECONDS := 8.0`
- `const COOLDOWN_SECONDS := 300.0`
- `const NEAR_ENEMY := 20.0`
- `const MAX_MOVEMENT := 0.45`

## Functions

### `has_enemy`

```gdscript
static func has_enemy(position: Vector3, zombies: Dictionary) -> bool
```

### `start_reason`

```gdscript
static func start_reason(world, player, zombies: Dictionary, now: float) -> String
```

### `cancel_reason`

```gdscript
static func cancel_reason(world, player, zombies: Dictionary, now: float) -> String
```

### `destination`

```gdscript
static func destination(world) -> Vector3
```

