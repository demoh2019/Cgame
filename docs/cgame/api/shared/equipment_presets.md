# equipment_presets.gd

> (no header comment)

`res://scripts/shared/equipment_presets.gd`

## Constants

- `const Defs = preload("res://scripts/shared/defs.gd")` - Three persistent, account-owned equipment shortcuts for classless role swaps. No item is moved, spawned, rented or copied: equip looks only in the authoritative carried inventory. Safe-hub access is enforced by GameServer.
- `const SLOT_COUNT := 3`

## Functions

### `empty_slots`

```gdscript
static func empty_slots() -> Array
```

### `valid_state`

```gdscript
static func valid_state(state: Variant) -> bool
```

Persisted data has only item IDs. No quantities, tier overrides, price,
XP, item creation, or client-provided equipment statistics are trusted.

### `save_slot`

```gdscript
static func save_slot(state: Array, index: int, carried) -> Dictionary
```

### `equip_slot`

```gdscript
static func equip_slot(state: Array, index: int, carried) -> Dictionary
```

### `clear_slot`

```gdscript
static func clear_slot(state: Array, index: int) -> Dictionary
```

_1 private function(s) starting with `_` are not listed._
