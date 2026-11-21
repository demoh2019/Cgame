# outlaw_bounty.gd

> Small, server-funded rewards for taking down wanted criminals in red/black zones.

`res://scripts/shared/outlaw_bounty.gd`

## Overview

Small, server-funded rewards for taking down wanted criminals in red/black zones.
The existing PvP honor ledger throttles repeated kills of the same account.

## Constants

- `const PvpInfamy = preload("res://scripts/shared/pvp_infamy.gd")`
- `const RED_BASE_SILVER := 15`
- `const BLACK_BASE_SILVER := 30`
- `const SILVER_PER_INFAMY_BRACKET := 10`
- `const INFAMY_BRACKET_SIZE := 25.0`
- `const MAX_BRACKETS := 2`

## Functions

### `silver_for`

```gdscript
static func silver_for(zone: int, infamy: float) -> int
```

Rewards scale with risk and the victim's verified server-owned infamy.
No payout for lawful self-defense against a non-outlaw.

### `reward_for_kill`

```gdscript
static func reward_for_kill(attacker, victim, zone: int, honor_result: Dictionary) -> int
```

Only authenticated, distinct accounts may earn currency. A genuinely
confirmed PvP kill with a fresh honor-ledger entry is also required.
Guests can still fight and earn normal noncurrency PvP honor.

