# camp_alarm.gd

> (no header comment)

`res://scripts/shared/camp_alarm.gd`

## Constants

- `const FieldCampfire = preload("res://scripts/shared/field_campfire.gd")` - Paid, temporary sentry alarm on a real server-owned campfire. Scans are bounded by a two-second cadence and reveal no enemy positions.
- `const ITEM_ID := "camp_alarm_kit"`
- `const ARM_RANGE := 3.2`
- `const ARM_HEIGHT := 2.5`
- `const MIN_FUEL_SECONDS := 45.0`
- `const DURATION := 180.0`
- `const SCAN_INTERVAL := 2.0`
- `const ALERT_COOLDOWN := 24.0`
- `const DETECTION_RADIUS := 21.0`
- `const DETECTION_HEIGHT := 8.0`
- `const MAX_DETECTED := 5`

## Functions

### `seconds_left`

```gdscript
static func seconds_left(fire: Dictionary, now: float) -> float
```

### `arm_reason`

```gdscript
static func arm_reason(fire: Dictionary, position: Vector3, now: float) -> String
```

### `install`

```gdscript
static func install(fire: Dictionary, owner_id: int, group_id: int, now: float) -> void
```

### `scan`

```gdscript
static func scan(fire: Dictionary, zombies: Dictionary, now: float, precomputed_count: int = -1) -> int
```

A positive result authorizes ONE private event, not an automatic attack.
No enemies are spawned, damaged, or exposed with exact coordinates.

