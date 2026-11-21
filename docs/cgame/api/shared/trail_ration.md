# trail_ration.gd

> (no header comment)

`res://scripts/shared/trail_ration.gd`

## Constants

- `const Defs = preload("res://scripts/shared/defs.gd")` - Durable smoked fish: server-owned light travel ration, never a combat buff. The remaining duration is persisted; no client passes a multiplier or tier.
- `const MAX_DURATION := 390.0`

## Functions

### `tier_for_food`

```gdscript
static func tier_for_food(item_id: String) -> int
```

### `duration`

```gdscript
static func duration(tier: int) -> float
```

### `hunger_savings`

```gdscript
static func hunger_savings(tier: int) -> float
```

### `valid_state`

```gdscript
static func valid_state(seconds: Variant, tier: Variant) -> bool
```

### `active_seconds`

```gdscript
static func active_seconds(remaining: float, delta: float) -> float
```

### `hunger_factor`

```gdscript
static func hunger_factor(tier: int, remaining: float, delta: float) -> float
```

Multiplier for a single tick. Integrates the active fraction exactly when
a buff ends midway through a long tick. 1.0 means ordinary hunger loss.

### `best_recipe`

```gdscript
static func best_recipe(inventory, crafting_level: int) -> String
```

Prefer the highest fish tier that is actually craftable from carried
ingredients, without bypassing the normal profession skill gate.

