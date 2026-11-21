# party_shield_wall.gd

> (no header comment)

`res://scripts/shared/party_shield_wall.gd`

## Constants

- `const GuardianTaunt = preload("res://scripts/shared/guardian_taunt.gd")` - Cooperative guardian Shield Wall. Only the authoritative server can arm it. It mitigates real infected melee damage to OTHER nearby party members. No PvP, acid, AoE or environmental branch calls this helper.
- `const RADIUS := 5.5`
- `const MAX_HEIGHT := 3.0`
- `const DURATION := 6.0`
- `const COOLDOWN := 32.0`
- `const ENERGY_COST := 30.0`
- `const DAMAGE_REDUCTION := 0.22`
- `const RAID_DAMAGE_REDUCTION := 0.12`

## Functions

### `can_protect`

```gdscript
static func can_protect(guardian, ally, parties, world) -> bool
```

Validate again at every melee hit. Position, gear, party and safety are
real server values, not data supplied by a requesting client.

### `protector_for`

```gdscript
static func protector_for(ally, players: Dictionary, parties, world) -> int
```

Bounded to current party roster (<=5); deterministic tie-breaker when
multiple guardians overlap. Stronger armor does not stack their auras.

### `mitigate`

```gdscript
static func mitigate(damage: float, raid_boss: bool) -> float
```

Flat percentage after armor, Dodge, Brace and Parry; wounds keep their
original wound-resistance rules and are not healed or erased by this buff.

