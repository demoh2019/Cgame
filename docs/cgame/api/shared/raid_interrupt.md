# raid_interrupt.gd

> Coordinated raid counterplay: two real party members can stop a telegraphed slam by landing attacks during its windup.

`res://scripts/shared/raid_interrupt.gd`

## Overview

Coordinated raid counterplay: two real party members can stop a telegraphed
slam by landing attacks during its windup. All values are server-owned.
One fighter's damage is capped so a solo burst never fakes teamwork.

## Constants

- `const MAX_DISTANCE := 12.0`
- `const CREDIT_PER_PLAYER := 16.0`
- `const REQUIRED_DAMAGE := 26.0`
- `const MIN_ATTACKERS := 2`
- `const MAX_ATTACKERS := 8`

## Functions

### `record_hit`

```gdscript
static func record_hit(warning: Dictionary, boss, peer_id: int, party_id: int, damage: float, now: float) -> bool
```

Mutates only this warning's ephemeral server-side contribution ledger.
True means the current warning has been interrupted; caller clears it.

### `public_progress`

```gdscript
static func public_progress(warning: Dictionary, now: float, viewer_party_id: int) -> Dictionary
```

Replicate only a bounded, anonymous damage tally. All parties can
see the empty objective; once somebody contributes, only their party
receives its progress. Never reveal peer IDs or private group IDs.

