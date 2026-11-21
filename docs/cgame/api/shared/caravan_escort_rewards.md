# caravan_escort_rewards.gd

> (no header comment)

`res://scripts/shared/caravan_escort_rewards.gd`

## Constants

- `const Inventory = preload("res://scripts/shared/inventory.gd")` - A party guard must actually escort a cargo carrier from its source. Only successful, server-resolved movement increments this session ledger. Shares come from the original courier payout: never mint bonus silver.
- `const CaravanRoutes = preload("res://scripts/shared/caravan_routes.gd")`
- `const CaravanAmbush = preload("res://scripts/shared/caravan_ambush.gd")`
- `const NightCaravan = preload("res://scripts/shared/night_caravan.gd")`
- `const START_RADIUS := 50.0`
- `const FOLLOW_RADIUS := 28.0`
- `const ARRIVAL_RADIUS := 20.0`
- `const MIN_ESCORT_METERS := 80.0`
- `const MAX_STEP_METERS := 4.0`
- `const MAX_ESCORT_SHARE := 0.20`

## Functions

### `record`

```gdscript
static func record(progress: Dictionary, courier_id: int, escort_id: int, group_id: int, route: Dictionary, courier_pos: Vector3, escort_pos: Vector3, actual_moved: float) -> void
```

Consecutive checkpoints at departure, 30%, 60%, 80%. A guard who
joins near the delivery point cannot retrospectively claim a trip.

### `qualifies`

```gdscript
static func qualifies(progress: Dictionary, courier_id: int, escort_id: int, group_id: int, route: Dictionary, courier_pos: Vector3, escort_pos: Vector3) -> bool
```

### `status`

```gdscript
static func status(progress: Dictionary, courier_id: int, escort_id: int, group_id: int, route: Dictionary) -> Dictionary
```

### `clear_peer`

```gdscript
static func clear_peer(progress: Dictionary, peer_id: int) -> void
```

### `settle`

```gdscript
static func settle(courier, escorts: Array, route: Dictionary, defended: bool = false, night_progress: Dictionary = {}) -> Dictionary
```

Stage all inventory changes before committing any. Escort money is
subtracted from the original courier payout; total remains unchanged.

_2 private function(s) starting with `_` are not listed._
