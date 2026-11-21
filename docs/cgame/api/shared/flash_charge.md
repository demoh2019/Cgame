# flash_charge.gd

> Short PvE-only group stun paid for by an actual workbench-crafted charge.

`res://scripts/shared/flash_charge.gd`

## Overview

Short PvE-only group stun paid for by an actual workbench-crafted charge.
The server derives impact and targets; existing blockers stop the throw
and the flash cannot bypass obstacles or stun raid bosses.

## Constants

- `const NoiseDecoy = preload("res://scripts/shared/noise_decoy.gd")`
- `const RangedCover = preload("res://scripts/shared/ranged_cover.gd")`
- `const ITEM_ID := "flash_charge"`
- `const RADIUS := 5.5`
- `const STAGGER_SECONDS := 1.25`
- `const MAX_TARGETS := 4`
- `const COOLDOWN_SECONDS := 12.0`
- `const PLAYER_NOISE_RADIUS := 28.0`
- `const NOISE_SECONDS := 1.8`

## Functions

### `landing`

```gdscript
static func landing(world, origin: Vector3, direction: Vector2) -> Dictionary
```

### `targets`

```gdscript
static func targets(world, site: Dictionary, enemies: Dictionary) -> Array
```

