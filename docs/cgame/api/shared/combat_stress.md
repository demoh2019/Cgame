# combat_stress.gd

> Short-lived PvE pursuit pressure.

`res://scripts/shared/combat_stress.gd`

## Overview

Short-lived PvE pursuit pressure. Combat stress is NOT a damage-over-time
effect, does not alter combat energy, and never exposes hidden enemy IDs.
Only living infected actively targeting a survivor can raise this meter.

## Constants

- `const Zombie = preload("res://scripts/shared/zombie.gd")`
- `const MAX_STRESS := 100.0`
- `const THREAT_RADIUS := 22.0`
- `const SUPPORT_RADIUS := 12.0`
- `const SCAN_SECONDS := 0.5`
- `const HUD_THRESHOLD := 10.0`
- `const RISE_PER_SECOND := 5.0`
- `const FIELD_RECOVERY_PER_SECOND := 2.0`
- `const SHELTER_RECOVERY_PER_SECOND := 5.0`
- `const HUB_RECOVERY_PER_SECOND := 10.0`
- `const ALLY_RISE_MULTIPLIER := 0.6`
- `const MAX_PRESSURE := 2.5`
- `const MAX_REGEN_PENALTY := 0.40`

## Functions

### `pressure`

```gdscript
static func pressure(zombies: Dictionary, peer_id: int, position: Vector3) -> float
```

Iterate server-owned, instantiated infected only. No client-provided
target coordinates, enemies or claimed visibility are accepted.

### `has_live_companion`

```gdscript
static func has_live_companion(peer_id: int, position: Vector3, players: Dictionary, parties) -> bool
```

Nearby and actually living party allies help avoid a solo stamina spiral.
Group membership is verified via the authoritative party registry.

### `advance`

```gdscript
static func advance(current: float, delta: float, pressure_value: float, safe_hub: bool, shelter: bool, supported: bool) -> float
```

No bonus is granted for fleeing fights by relogging: ephemeral pressure
simply goes to zero, as with respawning. No recoverable XP or currency.

### `regen_multiplier`

```gdscript
static func regen_multiplier(value: float) -> float
```

