# fishing.gd

> Shore fishing rules shared by server and tests.

`res://scripts/shared/fishing.gd`

## Overview

Shore fishing rules shared by server and tests. The client may only ask
the server to start casting: it cannot choose catch, tier or duration.
The rod is a carried tool, not an equippable weapon.

## Constants

- `const Defs = preload("res://scripts/shared/defs.gd")`
- `const FishingBait = preload("res://scripts/shared/fishing_bait.gd")`
- `const CAST_SECONDS := 5.0`
- `const COOLDOWN_SECONDS := 2.0`
- `const CATCH_ID := "raw_fish"`
- `const WATER_DISTANCES := [2.0, 2.8, 3.6]`
- `const WATER_SAMPLES := 16`
- `const MAX_CATCH := 2`
- `const BITE_WINDOW := 0.9`
- `const BITE_EARLIEST := 1.2 # Seconds after the cast starts.`
- `const BITE_LATEST_LEFT := 1.4 # Seconds left at the latest bite, so the window always fits in the cast.`
- `const HOOK_BONUS := 1`

## Functions

### `bite_at`

```gdscript
static func bite_at(cast_seconds: float, roll: float) -> float
```

Seconds left on the cast when the fish bites, from a roll in 0..1.

### `biting`

```gdscript
static func biting(remaining: float, bite_left: float) -> bool
```

Whether `remaining` seconds left on the cast fall inside the bite window.

### `water_near`

```gdscript
static func water_near(world, position: Vector3) -> Vector2
```

### `catch_tier`

```gdscript
static func catch_tier(zone: int, rod_tier: int, skill_tier: int) -> int
```

A region never produces fish above its own zone tier, the carried
fishing tool tier, or the survivor's server-owned profession tier.

### `catch_item`

```gdscript
static func catch_item(tier: int) -> String
```

### `validate_start`

```gdscript
static func validate_start(world, player_position: Vector3, backpack, skill_tier: int = 1, baited: bool = false) -> Dictionary
```

