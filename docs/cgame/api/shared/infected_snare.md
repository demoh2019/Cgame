# infected_snare.gd

> Field-built one-use snares stop roaming infected, not players or raid bosses.

`res://scripts/shared/infected_snare.gd`

## Overview

Field-built one-use snares stop roaming infected, not players or raid bosses.
Site, cost, lifetime and trigger are exclusively server-authoritative.

## Constants

- `const ITEM_ID := "infected_snare"`
- `const DURATION := 150.0`
- `const ROOT_SECONDS := 3.0`
- `const ELITE_ROOT_SECONDS := 1.5`
- `const TRIGGER_RADIUS := 1.35`
- `const BUILD_RANGE := 4.0`
- `const MIN_RANGE := 1.5`
- `const MIN_SEPARATION := 2.2`
- `const MAX_GLOBAL := 64`
- `const MAX_PER_OWNER := 3`

## Functions

### `valid_site`

```gdscript
static func valid_site(world, site: Vector2, origin: Vector2, existing: Dictionary) -> String
```

### `catches`

```gdscript
static func catches(trap: Dictionary, infected, now: float) -> bool
```

### `root_duration`

```gdscript
static func root_duration(infected) -> float
```

### `visible`

```gdscript
static func visible(traps: Dictionary, position: Vector3, now: float, radius: float) -> Array
```

