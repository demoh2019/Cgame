# pvp_infamy.gd

> Server-owned PvP reputation, only changed by confirmed lethal player hits.

`res://scripts/shared/pvp_infamy.gd`

## Overview

Server-owned PvP reputation, only changed by confirmed lethal player hits.

## Constants

- `const MAX_INFAMY := 100.0`
- `const INFAMY_PER_KILL := 25.0`
- `const OUTLAW_THRESHOLD := 50.0`
- `const SECONDS_PER_POINT := 180.0`
- `const SELF_DEFENSE_SECONDS := 30.0`

## Functions

### `defense_remaining`

```gdscript
static func defense_remaining(target_id: int, expiry: float, now: float) -> float
```

These temporary rights never appear in character saves or client RPCs.

### `can_retaliate`

```gdscript
static func can_retaliate(target_id: int, expiry: float, victim_id: int, now: float) -> bool
```

### `lawful_kill_reason`

```gdscript
static func lawful_kill_reason(score: float, target_id: int, expiry: float, victim_id: int, now: float) -> String
```

### `valid`

```gdscript
static func valid(value: Variant) -> bool
```

### `is_outlaw`

```gdscript
static func is_outlaw(score: float) -> bool
```

### `gain_for_kill`

```gdscript
static func gain_for_kill(score: float) -> float
```

### `decay`

```gdscript
static func decay(score: float, seconds: float) -> float
```

### `vendor_unit_price`

```gdscript
static func vendor_unit_price(base_price: int, score: float, buy: bool) -> int
```

Price for one item, independent of batch size (no split-order exploit).
Infamy raises buy prices at most 50% and lowers sell prices at most 25%.

