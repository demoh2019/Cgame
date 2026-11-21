# raid_ward.gd

> (no header comment)

`res://scripts/shared/raid_ward.gd`

## Constants

- `const PERCENT_PER_GUARD := 12` - Live server-spawned raid minions grant their boss temporary resistance. Never accepts an RPC, persists state or changes damage against players.
- `const MAX_EFFECTIVE_GUARDS := 2`

## Functions

### `living_count`

```gdscript
static func living_count(boss, active_boss_id: int, guard_ids: Array[int], zombies: Dictionary) -> int
```

### `reduction_percent`

```gdscript
static func reduction_percent(guards: int) -> int
```

### `absorb`

```gdscript
static func absorb(damage: float, boss, active_boss_id: int, guard_ids: Array[int], zombies: Dictionary) -> float
```

