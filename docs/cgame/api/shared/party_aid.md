# party_aid.gd

> Authoritative, equipment-independent field medic support for survivor parties.

`res://scripts/shared/party_aid.gd`

## Overview

Authoritative, equipment-independent field medic support for survivor parties.
Client requests only recipient and carried item; server owns all other rules.

## Constants

- `const Defs = preload("res://scripts/shared/defs.gd")`
- `const WoundSealant = preload("res://scripts/shared/wound_sealant.gd")`
- `const RANGE := 3.2`
- `const MAX_HEIGHT_DIFF := 2.5`
- `const COOLDOWN := 5.0`

## Functions

### `can_reach`

```gdscript
static func can_reach(source: Vector3, target: Vector3) -> bool
```

### `supported_item`

```gdscript
static func supported_item(item_id: String, item_data: Dictionary) -> bool
```

Only plain provisions can be handed over. Special meals and potions retain
their separate gameplay rules; clients cannot submit an arbitrary item ID.

### `has_effect`

```gdscript
static func has_effect(item_data: Dictionary, health: float, infection: float, bleeding: float = 0.0, fracture: float = 0.0, hunger: float = 100.0, thirst: float = 100.0, max_health: float = Defs.MAX_HEALTH, food_poisoning: float = 0.0) -> bool
```

### `medical_items`

```gdscript
static func medical_items() -> Array[String]
```

One catalog for the UI and server, so newly crafted medical items work in
cooperative play without maintaining a second, incomplete whitelist.

### `best_item`

```gdscript
static func best_item(inventory, health: float, infection: float, bleeding: float, fracture: float, max_health: float = Defs.MAX_HEALTH, food_poisoning: float = 0.0) -> String
```

Automatic field aid is a convenience request, never a client-selected target
condition. Use the cheapest carried remedy for the most urgent treatable
condition: bleeding, fracture, infection, then missing health.
Manual item selection stays available for deliberate expensive treatments.

