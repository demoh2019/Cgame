# acid_neutralizer.gd

> One-use field chemistry for clearing lingering infected acid.

`res://scripts/shared/acid_neutralizer.gd`

## Overview

One-use field chemistry for clearing lingering infected acid.
The client supplies only the item-use request; the server picks pools.
Direct spitter impacts and already-applied damage are never reversed.

## Constants

- `const AcidSpitter = preload("res://scripts/shared/acid_spitter.gd")`
- `const ITEM_ID := "field_alkali_kit"`
- `const RANGE := 5.5`
- `const MAX_CLEARED := 3`

## Functions

### `targets`

```gdscript
static func targets(pools: Dictionary, position: Vector3, now: float) -> Array[int]
```

Returns stable, closest-first server IDs; ignores expired/invalid pools.

