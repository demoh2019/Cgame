# combat_logout.gd

> (no header comment)

`res://scripts/shared/combat_logout.gd`

## Constants

- `const ZoneRisk = preload("res://scripts/shared/zone_risk.gd")` - PvP combat-tag rules for full-loot server disconnects. Server time only; clients never provide tags, damage, last-hit timestamps or logout status.
- `const TAG_SECONDS := 30.0`

## Functions

### `mark`

```gdscript
static func mark(player, now: float) -> void
```

### `remaining`

```gdscript
static func remaining(expires: float, now: float) -> float
```

### `penalize_on_disconnect`

```gdscript
static func penalize_on_disconnect(player, zone: int, now: float) -> bool
```

