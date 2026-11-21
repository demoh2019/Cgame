# infected_target_utility.gd

> Infected prey choice scored with Utility AI instead of "nearest wins": proximity still dominates, but a wounded straggler, the survivor already being chased,...

`res://scripts/shared/infected_target_utility.gd`

## Overview

Infected prey choice scored with Utility AI instead of "nearest wins":
proximity still dominates, but a wounded straggler, the survivor already
being chased, and a noisy survivor each tip the balance — the horde hunts
the weak and does not flip-flop between two equally close players.

## Constants

- `const UtilityAI = preload("res://scripts/shared/utility_ai.gd")`
- `const WOUNDED_BONUS := 0.35`
- `const STICKY_BONUS := 0.25`
- `const NOISE_BONUS := 0.15`

## Functions

### `score`

```gdscript
static func score(distance: float, leash: float, health_fraction: float, is_current: bool, noisy: bool) -> float
```

