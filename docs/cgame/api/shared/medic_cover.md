# medic_cover.gd

> (no header comment)

`res://scripts/shared/medic_cover.gd`

## Constants

- `const Defs = preload("res://scripts/shared/defs.gd")` - Combat healer's emergency cover request: transfers only CURRENT infected aggro to one equipped nearby party guardian, with server-only target selection. Infected not already fighting/aware of the medic are never provoked.
- `const GuardianTaunt = preload("res://scripts/shared/guardian_taunt.gd")`
- `const Threat = preload("res://scripts/shared/threat.gd")`
- `const Zombie = preload("res://scripts/shared/zombie.gd")`
- `const RADIUS := 8.0`
- `const ENEMY_RADIUS := 16.0`
- `const MAX_HEIGHT := 3.0`
- `const MAX_ENEMIES := 3`
- `const ENERGY_COST := 24.0`
- `const COOLDOWN := 30.0`
- `const TAUNT_SECONDS := 2.0`
- `const RETAINED_THREAT := 0.35`

## Functions

### `has_staff`

```gdscript
static func has_staff(medic) -> bool
```

### `guardian_ok`

```gdscript
static func guardian_ok(medic, guardian, parties, world) -> bool
```

### `guardian_for`

```gdscript
static func guardian_for(medic, players: Dictionary, parties, world)
```

Unique guardian nearest to the caster, stable peer-ID ties.

### `can_redirect`

```gdscript
static func can_redirect(infected, medic, guardian, world) -> bool
```

No boss manipulation, idle/wandering pack aggro, other parties, cross-zone
threats, remote transfers, or overwriting an unrelated active taunt.

### `fade_threat`

```gdscript
static func fade_threat(infected, medic_id: int) -> void
```

Fold only the medic's existing, finite hate. Zombie.force_taunt adds its
own bounded guardian threat and a short target-lock; no fabricated heals.

