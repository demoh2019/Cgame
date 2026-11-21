# loot_sweep.gd

> (no header comment)

`res://scripts/shared/loot_sweep.gd`

## Constants

- `const Defs = preload("res://scripts/shared/defs.gd")` - Deterministic, reach-limited candidates for optional bulk PvE scavenging. The client sends no bag IDs; special and unowned bags remain manual.
- `const LootRights = preload("res://scripts/shared/loot_rights.gd")`
- `const MAX_BAGS := 5`
- `const COOLDOWN := 1.5`
- `const RADIUS := Defs.REACH + 0.5`

## Functions

### `candidates`

```gdscript
static func candidates(bags: Dictionary, at: Vector3, player, now: float) -> Array[int]
```

