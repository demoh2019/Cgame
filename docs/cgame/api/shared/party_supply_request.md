# party_supply_request.gd

> Server-side requirements for temporary group food and water alerts.

`res://scripts/shared/party_supply_request.gd`

## Overview

Server-side requirements for temporary group food and water alerts.
Never trust a client-reported survival stat, timestamp or position.

## Constants

- `const NEED_THRESHOLD := 60.0`
- `const COOLDOWN := 30.0`
- `const ALERT_SECONDS := 45.0 # Temporary aid location; no persistent tracking.`

## Functions

### `valid_need`

```gdscript
static func valid_need(need: String) -> bool
```

### `level`

```gdscript
static func level(need: String, hunger: float, thirst: float) -> float
```

### `eligible`

```gdscript
static func eligible(need: String, hunger: float, thirst: float) -> bool
```

### `can_send`

```gdscript
static func can_send(now: float, last_at: float) -> bool
```

