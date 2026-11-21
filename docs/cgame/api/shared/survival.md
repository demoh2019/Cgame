# survival.gd

> A player's vital statistics and the rules that change them over time.

`res://scripts/shared/survival.gd`

## Overview

A player's vital statistics and the rules that change them over time.

## Constants

- `const Defs = preload("res://scripts/shared/defs.gd")`
- `const FoodSafety = preload("res://scripts/shared/food_safety.gd")`

## Functions

### `can_sprint_with`

```gdscript
static func can_sprint_with(value: float, hunger_value: float, thirst_value: float, seconds: float) -> bool
```

The same eligibility math runs on the server and client prediction.

### `try_sprint`

```gdscript
func try_sprint(seconds: float) -> bool
```

### `tick`

```gdscript
func tick(delta: float) -> float
```

Advances the clock. Returns the damage taken from hunger or thirst this step.

### `weather_tick`

```gdscript
func weather_tick(delta: float, severity: float) -> float
```

Called only by the server with a computed weather severity (0..1).
Exposure decays while sheltered or when conditions improve. High sustained
cold/wet exposure deals real health damage; zero shelter never mints health.

### `hurt`

```gdscript
func hurt(amount: float) -> float
```

Returns the damage that was applied (after clamping at 0 health).

### `heal`

```gdscript
func heal(amount: float) -> void
```

### `eat`

```gdscript
func eat(amount: float) -> void
```

### `drink`

```gdscript
func drink(amount: float) -> void
```

### `add_food_poisoning`

```gdscript
func add_food_poisoning(amount: float) -> bool
```

### `treat_food_poisoning`

```gdscript
func treat_food_poisoning(amount: float) -> bool
```

### `add_infection`

```gdscript
func add_infection(amount: float) -> bool
```

### `treat_infection`

```gdscript
func treat_infection(amount: float) -> bool
```

### `add_bleeding`

```gdscript
func add_bleeding(amount: float) -> bool
```

Call only when an actual attack inflicted damage; fake client wounds are ignored.

### `stop_bleeding`

```gdscript
func stop_bleeding() -> bool
```

### `add_fracture`

```gdscript
func add_fracture(amount: float) -> bool
```

The server consumes an actual heat pack only if there is no current buff.
Only a real damaging hit can call this on the authoritative server.

### `treat_fracture`

```gdscript
func treat_fracture(amount: float) -> bool
```

### `fracture_speed_factor`

```gdscript
static func fracture_speed_factor(severity: float) -> float
```

### `apply_thermal_wrap`

```gdscript
func apply_thermal_wrap() -> bool
```

### `reset`

```gdscript
func reset() -> void
```

### `to_dict`

```gdscript
func to_dict() -> Dictionary
```

_1 private function(s) starting with `_` are not listed._
