# ruin_ambush.gd

> A real red/black-zone ruin cache can wake a finite infected pack.

`res://scripts/shared/ruin_ambush.gd`

## Overview

A real red/black-zone ruin cache can wake a finite infected pack.
Only the authoritative server knows the crate, world seed and loot result.
No bonus treasure is minted and spawned enemies occupy no respawn slot.

## Constants

- `const WorldGen = preload("res://scripts/shared/world_gen.gd")`
- `const SupplyDrops = preload("res://scripts/shared/supply_drops.gd")`
- `const ZoneRisk = preload("res://scripts/shared/zone_risk.gd")`
- `const MAX_ACTIVE_INFECTED := 88`
- `const MAX_ACTIVE_WAVES := 3`
- `const COOLDOWN_SECONDS := 90.0`
- `const LIFETIME_SECONDS := 150.0`
- `const RED_WAKE_CHANCE := 35`
- `const BLACK_WAKE_CHANCE := 60`

## Functions

### `awakens`

```gdscript
static func awakens(zone: int, crate_id: int, world_seed: int, lockpicked: bool) -> bool
```

Sealed compartments are always noisy; ordinary crates have a stable
per-site chance. The roll cannot be rerolled by logout or waiting.

### `available`

```gdscript
static func available(active: Array, infected: Dictionary) -> int
```

### `record_kill`

```gdscript
static func record_kill(wave: Dictionary, infected_id: int) -> bool
```

A genuine server-confirmed zombie death is counted at most once. A
despawn, missing ID, duplicate callback or forged kill never wins a wave.

### `sites`

```gdscript
static func sites(world, crate: Dictionary, survivors: Array[Vector3], infected: Dictionary, capacity: int, angle_offset: int = 0) -> Array[Dictionary]
```

Reuses the same safe, collision-checked ring as guarded supply drops.
The given crate zone MUST match real terrain; no target coordinates or
enemy type are supplied by a player or network request.

