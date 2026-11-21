# party_feast.gd

> Server-controlled shared camp meal.

`res://scripts/shared/party_feast.gd`

## Overview

Server-controlled shared camp meal. Never accept client-reported party members,
positions, fire status, food quantity, meal tier, or recovery bonuses.

## Constants

- `const FieldCampfire = preload("res://scripts/shared/field_campfire.gd")`
- `const HeartyMeal = preload("res://scripts/shared/hearty_meal.gd")`
- `const COOLDOWN := 20.0`
- `const MAX_HEIGHT_DIFFERENCE := 2.5`

## Functions

### `near_fire`

```gdscript
static func near_fire(camp: Dictionary, position: Vector3, now: float) -> bool
```

### `camp_for`

```gdscript
static func camp_for(campfires: Dictionary, position: Vector3, now: float) -> Dictionary
```

Choose a real active server campfire, never a site or ID sent by the client.

### `food_tier`

```gdscript
static func food_tier(item_id: String) -> int
```

