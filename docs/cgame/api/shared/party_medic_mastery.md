# party_medic_mastery.gd

> Authoritative medicine mastery for parties.

`res://scripts/shared/party_medic_mastery.gd`

## Overview

Authoritative medicine mastery for parties. No client-provided bonus or XP.
PvP-safe group treatment uses a smaller cap than self-healing perks.

## Constants

- `const MAX_PARTY_HEAL_BONUS := 0.35`
- `const MAX_TRAINING_XP := 5.0`
- `const MIN_TRAINING_EFFORT := 1.0`

## Functions

### `heal_amount`

```gdscript
static func heal_amount(base_amount: float, medic_bonus: float) -> float
```

Returns the amount to hand to Survival.heal, not the actual credited heal.
The server measures real HP restored after the recipient's max-HP clamp.

### `training_xp`

```gdscript
static func training_xp(healed: float, bleeding_stopped: float, infection_cured: float, fracture_treated: float, poisoning_treated: float) -> float
```

Real inventory-paid medical effects train the Medic skill, never supplies,
idle casts or failed RPCs. Do not award points for tiny/no-op health changes.
Each action has a hard XP cap, including three-target group triage.

