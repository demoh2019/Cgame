# antiseptic_edge.gd

> (no header comment)

`res://scripts/shared/antiseptic_edge.gd`

## Constants

- `const Defs = preload("res://scripts/shared/defs.gd")` - Paid, short-lived melee weapon preparation for ordinary infected hunts. This does not modify PvP, raid-boss damage or raw weapon item definitions.
- `const ITEM_ID := "antiseptic_edge_oil"`
- `const SECONDS := 120.0`
- `const DAMAGE_BONUS := 0.20`

## Functions

### `melee_equipped`

```gdscript
static func melee_equipped(inventory) -> bool
```

### `use_reason`

```gdscript
static func use_reason(inventory, remaining: float) -> String
```

### `still_valid`

```gdscript
static func still_valid(inventory, coated_weapon: String, remaining: float, alive: bool = true) -> bool
```

### `damage`

```gdscript
static func damage(amount: float, inventory, coated_weapon: String, remaining: float, infected) -> float
```

Call only in the authoritative "zombie" hit branch, never PvP.

### `tick`

```gdscript
static func tick(inventory, coated_weapon: String, remaining: float, delta: float, alive: bool = true) -> float
```

