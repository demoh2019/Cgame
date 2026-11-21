# campfire_threat.gd

> Field campfires trade shelter for stealth at night.

`res://scripts/shared/campfire_threat.gd`

## Overview

Field campfires trade shelter for stealth at night. All cues are server-owned.
A cell-based index keeps light lures cheap when many camps are active.

## Constants

- `const FieldCampfire = preload("res://scripts/shared/field_campfire.gd")`
- `const REVEAL_RADIUS := 30.0`
- `const LURE_RADIUS := 26.0`

## Functions

### `reveal_radius`

```gdscript
static func reveal_radius(fires: Dictionary, survivor: Vector3, now: float, night: bool) -> float
```

### `light_buckets`

```gdscript
static func light_buckets(fires: Dictionary, now: float, night: bool) -> Dictionary
```

Exclude expired or invalid fires even before the next world cleanup pass.

### `nearest_light`

```gdscript
static func nearest_light(buckets: Dictionary, infected: Vector3) -> Dictionary
```

Only the same or neighboring grid cells could contain an audible light.
Equal-distance results are deterministic by persistent world fire ID.

