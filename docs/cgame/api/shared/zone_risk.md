# zone_risk.gd

> Authoritative world risk.

`res://scripts/shared/zone_risk.gd`

## Overview

Authoritative world risk. Yellow is PvE-only in this MVP.

## Constants

- `const Defs = preload("res://scripts/shared/defs.gd")`

## Functions

### `allows_pvp`

```gdscript
static func allows_pvp(zone: int) -> bool
```

### `can_pvp`

```gdscript
static func can_pvp(attacker_zone: int, victim_zone: int) -> bool
```

### `full_loot`

```gdscript
static func full_loot(zone: int) -> bool
```

### `description`

```gdscript
static func description(zone: int) -> String
```

### `lawless`

```gdscript
static func lawless(zone: int) -> bool
```

Albion-style black zone: the outermost ring is lawless - player kills there cost no infamy.

