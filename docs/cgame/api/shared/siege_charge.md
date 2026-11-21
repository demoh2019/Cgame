# siege_charge.gd

> A physical PvP siege charge: server picks the nearest wall and owns its fuse.

`res://scripts/shared/siege_charge.gd`

## Overview

A physical PvP siege charge: server picks the nearest wall and owns its fuse.
No client-provided wall id, explosive damage or detonation time.

## Constants

- `const BarricadeBallistics = preload("res://scripts/shared/barricade_ballistics.gd")`
- `const NoiseDecoy = preload("res://scripts/shared/noise_decoy.gd")`
- `const RangedCover = preload("res://scripts/shared/ranged_cover.gd")`
- `const Structures = preload("res://scripts/shared/structures.gd")`
- `const ZoneRisk = preload("res://scripts/shared/zone_risk.gd")`
- `const ITEM_ID := "siege_charge"`
- `const PLANT_REACH := 3.5`
- `const FUSE_SECONDS := 4.0`
- `const DAMAGE := 160.0`
- `const MAX_ACTIVE := 24`
- `const MAX_PER_OWNER := 1`
- `const MAX_PER_WALL := 1`
- `const NOISE_RADIUS := NoiseDecoy.HEARING_RADIUS`
- `const NOISE_SECONDS := 2.5`

## Functions

### `owner_token`

```gdscript
static func owner_token(player) -> String
```

Match a stable account across reconnections; guests use instance identity,
never an untrusted or recycled transport peer number.

### `nearest_wall`

```gdscript
static func nearest_wall(world, player, walls: Dictionary) -> Dictionary
```

Select from real world structures. If a protected wall is nearest, the
server does NOT silently skip it to damage an enemy wall behind it.

### `placement_reason`

```gdscript
static func placement_reason(charges: Dictionary, wall_id: int, player) -> String
```

### `valid_detonation`

```gdscript
static func valid_detonation(world, charge: Dictionary, walls: Dictionary) -> bool
```

Detached charges are session-only, and only the same world-owned
barricade at the original position can take damage after the fuse.

