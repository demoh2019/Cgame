# reputation.gd

> Persistent survivor renown: earned only by verified server gameplay.

`res://scripts/shared/reputation.gd`

## Overview

Persistent survivor renown: earned only by verified server gameplay.
Rank determines modest NPC survival-supply discounts, not PvP power,
loot duplication, player-to-player prices or global market taxes.

## Constants

- `const SaveValidation = preload("res://scripts/shared/save_validation.gd")`
- `const MAX_RENOWN := 10000`
- `const RANK_POINTS := [0, 40, 160, 500]`
- `const RANK_NAMES := ["Newcomer", "Settler", "Ranger", "Warden"]`
- `const SHOP_DISCOUNTS := [0, 10, 15, 20]`
- `const CONTRACT_RENOWN := 8`

## Functions

### `valid_points`

```gdscript
static func valid_points(raw: Variant) -> bool
```

### `rank`

```gdscript
static func rank(points: int) -> int
```

### `title`

```gdscript
static func title(points: int) -> String
```

### `discount_percent`

```gdscript
static func discount_percent(points: int) -> int
```

### `next_threshold`

```gdscript
static func next_threshold(points: int) -> int
```

### `apply_earned`

```gdscript
static func apply_earned(current: int, earned: int) -> int
```

### `kill_points`

```gdscript
static func kill_points(zombie_type: String, elite: bool, raid_boss: bool) -> int
```

### `buy_price`

```gdscript
static func buy_price(base_price: int, quantity: int, renown: int) -> int
```

