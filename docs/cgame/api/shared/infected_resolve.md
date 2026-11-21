# infected_resolve.gd

> Server-side diminishing returns for repeated PvE staggers.

`res://scripts/shared/infected_resolve.gd`

## Overview

Server-side diminishing returns for repeated PvE staggers.
Native GameplayEffectStackPolicy implements the reusable GAS stacking rules.
Stock Godot uses identical formulas, preserving existing combat and PvP isolation.

## Constants

- `const RESET_SECONDS := 6.0`
- `const MAX_STACKS := 3`
- `const FACTORS := [1.0, 0.65, 0.40]`

## Functions

### `duration`

```gdscript
static func duration(base: float, stacks: int, elite: bool) -> float
```

Deterministic effect duration; no authority transfer to clients.

### `plan_application`

```gdscript
static func plan_application(base: float, stacks: int, current_remaining: float, elite: bool) -> Dictionary
```

Non-mutating application proposal. Only successful applications consume
one Resolve stack and reset the six-second recovery window.

### `remaining`

```gdscript
static func remaining(seconds: float, delta: float) -> float
```

_1 private function(s) starting with `_` are not listed._
