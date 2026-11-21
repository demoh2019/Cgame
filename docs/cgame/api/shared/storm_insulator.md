# storm_insulator.gd

> (no header comment)

`res://scripts/shared/storm_insulator.gd`

## Constants

- `const ITEM_ID := "storm_insulator"` - Craftable, persisted, server-owned shock mitigation; only lightning uses it.
- `const DURATION_SECONDS := 180.0`
- `const DAMAGE_REDUCTION := 0.60`

## Functions

### `active`

```gdscript
static func active(seconds: float) -> bool
```

### `apply_reason`

```gdscript
static func apply_reason(seconds: float) -> String
```

### `lightning_damage`

```gdscript
static func lightning_damage(base: float, seconds: float) -> float
```

### `remaining`

```gdscript
static func remaining(seconds: float, delta: float) -> float
```

