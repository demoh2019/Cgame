# contracts.gd

> Finite camp contracts that connect survival scavenging, classless crafting and infected PvE.

`res://scripts/shared/contracts.gd`

## Overview

Finite camp contracts that connect survival scavenging, classless crafting
and infected PvE. All state transitions run on the authoritative server.
No client-supplied reward, quantity, progress or target ID is trusted.

## Constants

- `const Inventory = preload("res://scripts/shared/inventory.gd")`
- `const SaveValidation = preload("res://scripts/shared/save_validation.gd")`
- `const ORDER := ["camp_supplies", "weapon_training", "infected_patrol", "ruin_recovery"]`
- `const CATALOG := {`

## Functions

### `empty_state`

```gdscript
static func empty_state() -> Dictionary
```

### `valid_state`

```gdscript
static func valid_state(data: Variant) -> bool
```

### `description`

```gdscript
static func description(state: Dictionary) -> String
```

### `accept`

```gdscript
static func accept(state: Dictionary) -> Dictionary
```

### `record_kill`

```gdscript
static func record_kill(state: Dictionary) -> bool
```

### `record_crate`

```gdscript
static func record_crate(state: Dictionary, crate_id: int) -> bool
```

One server-confirmed ruin cache only counts once for the character,
even if the physical cache refills later.

### `claim`

```gdscript
static func claim(carried, state: Dictionary) -> Dictionary
```

