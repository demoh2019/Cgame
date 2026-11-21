# raid_tempo.gd

> (no header comment)

`res://scripts/shared/raid_tempo.gd`

## Constants

- `const GOLD_LIMIT := 90.0` - Optional raid tempo chest bonus: only the authoritative encounter clock decides the tier; normal zombies and ordinary boss treasure are unchanged.
- `const SILVER_LIMIT := 150.0`

## Functions

### `rank`

```gdscript
static func rank(elapsed: float) -> String
```

### `bonus`

```gdscript
static func bonus(zone: int, elapsed: float) -> Dictionary
```

