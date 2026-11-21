# party_triage.gd

> Item-paid, server-only group triage after battles.

`res://scripts/shared/party_triage.gd`

## Overview

Item-paid, server-only group triage after battles.
This helper is pure: clients cannot supply recipients, effects or positions.

## Constants

- `const ITEM_ID := "field_triage_pack"`
- `const RANGE := 5.5`
- `const HEIGHT_LIMIT := 2.5`
- `const MAX_RECIPIENTS := 3`
- `const HEAL := 18.0`
- `const BLEEDING_TREATMENT := 24.0`
- `const COOLDOWN := 18.0`

## Functions

### `can_reach`

```gdscript
static func can_reach(source: Vector3, target: Vector3) -> bool
```

### `urgency`

```gdscript
static func urgency(health: float, max_health: float, bleeding: float) -> float
```

Greater score receives care first. Never treat healthy or invalid targets.

