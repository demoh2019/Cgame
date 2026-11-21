# finishing_strike.gd

> Deterministic, equipment-only PvE finisher.

`res://scripts/shared/finishing_strike.gd`

## Overview

Deterministic, equipment-only PvE finisher. The player supplies no target
health, hit multiplier, boss status, or threshold. This helper is pure.

## Constants

- `const THRESHOLD := 0.35`
- `const NORMAL_MULTIPLIER := 2.0`
- `const ELITE_MULTIPLIER := 1.5`
- `const RAID_BOSS_MULTIPLIER := 1.2`

## Functions

### `multiplier`

```gdscript
static func multiplier(health: float, max_health: float, is_elite: bool, is_raid_boss: bool) -> float
```

Called only for a real infected hit, BEFORE base damage is applied.
Do not reward finishing dead, overhealed, or nonfinite enemies.

