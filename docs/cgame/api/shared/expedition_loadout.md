# expedition_loadout.gd

> Server-owned consumable loadouts: withdrawals only, never purchased or generated items.

`res://scripts/shared/expedition_loadout.gd`

## Overview

Server-owned consumable loadouts: withdrawals only, never purchased or
generated items. Presets are immutable and each is bounded to item stacks.

## Constants

- `const Defs = preload("res://scripts/shared/defs.gd")`
- `const Inventory = preload("res://scripts/shared/inventory.gd")`
- `const ORDER := ["scout", "archer", "gunner", "medic", "miner"]`
- `const TARGETS := {`
- `const NAMES := {"scout": "Scout", "archer": "Archer", "gunner": "Gunner", "medic": "Medic", "miner": "Miner"}`

## Functions

### `title`

```gdscript
static func title(preset_id: String) -> String
```

### `valid_preset`

```gdscript
static func valid_preset(preset_id: String) -> bool
```

### `restock`

```gdscript
static func restock(carried, protected_bank, preset_id: String) -> Dictionary
```

Stage two inventory snapshots and commit only after every proposed
transfer succeeds. Count already carried supplies against target, leaving
extra carried items intact. Missing bank stock and full slots are skipped.

