# field_canteen.gd

> Two server-gated ways to bottle clean shoreline water.

`res://scripts/shared/field_canteen.gd`

## Overview

Two server-gated ways to bottle clean shoreline water. This helper performs
only atomic inventory conversion; GameServer authorizes the lake and fire.

## Constants

- `const Inventory = preload("res://scripts/shared/inventory.gd")`
- `const CANTEEN_ITEM := "field_canteen"`
- `const FILTER_ITEM := "charcoal_filter"`
- `const OUTPUT_ITEM := "water_bottle"`
- `const OUTPUT_COUNT := 1`
- `const BOIL_FUEL := "wood_1"`
- `const BOIL_FUEL_COUNT := 2`
- `const BOIL_RADIUS := 3.2`
- `const BOIL_MAX_HEIGHT := 3.0`

## Functions

### `can_boil`

```gdscript
static func can_boil(campfires: Dictionary, position: Vector3, now: float) -> bool
```

Fire placement, expiry and ownership stay on the server. A survivor can
share a neighbor's burning fire but cannot boil from another elevation.

### `fill`

```gdscript
static func fill(backpack) -> String
```

Traditional filtration: consumes a single charcoal filter.

### `boil`

```gdscript
static func boil(backpack) -> String
```

Alternative lakeside survival loop: an existing fire plus two units of
firewood, without using a disposable charcoal filter.

_1 private function(s) starting with `_` are not listed._
