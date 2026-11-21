# siege_contracts.gd

> Server-owned siege challenges for existing parties, not permanent Nakama guild wars.

`res://scripts/shared/siege_contracts.gd`

## Overview

Server-owned siege challenges for existing parties, not permanent Nakama guild wars.
Cost is paid when declared; combat/capture remains governed by TerritoryControl.
A victory needs a real capture event inside the announced attack window.

## Constants

- `const DECLARE_RADIUS := 24.0`
- `const MIN_ATTACKERS := 2`
- `const PREPARATION_SECONDS := 20.0`
- `const ATTACK_SECONDS := 180.0`
- `const SITE_COOLDOWN := 300.0`
- `const MIN_REMAINING_CONTROL := 80.0 # Preparation + worst-case fortified capture time.`
- `const COST := {"cloth_2": 2, "silver": 25}`

## Functions

### `declare`

```gdscript
func declare(site: Dictionary, inventory, player_position: Vector3, group_id: int, is_leader: bool, nearby_allies: int, now: float) -> Dictionary
```

### `public_state`

```gdscript
func public_state(outposts: Array, now: float) -> Array
```

Read-only client view; does not disclose account IDs or private inventories.

### `tick`

```gdscript
func tick(now: float, sites: Array, parties, capture_events: Array) -> Array
```

Must run after the normal territory tick. Only its capture events may win a war.

