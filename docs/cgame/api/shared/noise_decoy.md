# noise_decoy.gd

> Craftable thrown noise lures for stealthy survivor expeditions.

`res://scripts/shared/noise_decoy.gd`

## Overview

Craftable thrown noise lures for stealthy survivor expeditions.
Server-owned positions, costs and expiry; no fake player aggro or damage.

## Constants

- `const ITEM_ID := "noise_decoy"`
- `const THROW_DISTANCE := 8.0`
- `const HEARING_RADIUS := 23.0`
- `const DURATION := 8.0`
- `const COOLDOWN := 3.0`
- `const MAX_ACTIVE := 48`
- `const MAX_PER_OWNER := 2`
- `const MAX_COORD := 20000.0`

## Functions

### `landing`

```gdscript
static func landing(world, origin: Vector3, direction: Vector2) -> Dictionary
```

Returns a validated landing site. A requested direction is NOT an
arbitrary client destination; the server derives all world coordinates.

### `is_audible`

```gdscript
static func is_audible(decoy: Dictionary, position: Vector3, now: float) -> bool
```

### `visible_state`

```gdscript
static func visible_state(decoy: Dictionary, now: float) -> Dictionary
```

### `sound_buckets`

```gdscript
static func sound_buckets(decoys: Dictionary, now: float) -> Dictionary
```

Grid size equals hearing radius: any audible lure is in the same or
an immediately adjacent cell. Build once per scheduled AI hearing pass.
Avoid comparing every infected against every planted lure.

### `closest_audible`

```gdscript
static func closest_audible(buckets: Dictionary, position: Vector3, now: float) -> Dictionary
```

Return the closest audible active lure, tie-breaking by stable world ID.
No player IDs, account data or client-supplied detection distances involved.

