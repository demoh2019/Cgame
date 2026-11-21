# bike_chain.gd

> Bicycle hearing is a tradeoff for mounted travel speed.

`res://scripts/shared/bike_chain.gd`

## Overview

Bicycle hearing is a tradeoff for mounted travel speed. Only a consumed kit
lowers the radius; gunshots, footfalls, scent and visibility remain unchanged.

## Constants

- `const Mounts = preload("res://scripts/shared/mounts.gd")`
- `const ITEM_ID := "bike_chain_wrap"`
- `const DURATION_SECONDS := 180.0`
- `const RIDING_NOISE_RADIUS := Mounts.NOISE_RADIUS`
- `const WRAPPED_NOISE_RADIUS := 9.0`
- `const SOUND_SECONDS := Mounts.NOISE_SECONDS`

## Functions

### `apply_reason`

```gdscript
static func apply_reason(inventory, remaining: float) -> String
```

### `riding_radius`

```gdscript
static func riding_radius(remaining: float) -> float
```

