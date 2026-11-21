# combat.gd

> Damage rules and loot tables.

`res://scripts/shared/combat.gd`

## Overview

Damage rules and loot tables.

## Constants

- `const Defs = preload("res://scripts/shared/defs.gd")`
- `const WorldGen = preload("res://scripts/shared/world_gen.gd")`
- `const RestorationStaff = preload("res://scripts/shared/restoration_staff.gd")`
- `const FinishingStrike = preload("res://scripts/shared/finishing_strike.gd")`
- `const SunderMark = preload("res://scripts/shared/sunder_mark.gd")`

## Functions

### `apply_armor`

```gdscript
static func apply_armor(damage: float, armor_id: String) -> float
```

Damage after the target's armour. `armor_id` may be empty.

### `apply_gear`

```gdscript
static func apply_gear(damage: float, inventory) -> float
```

Damage after everything worn: body armor plus hood, cloak, gloves and boots, at most 80% blocked.

### `infected_wound_amount`

```gdscript
static func infected_wound_amount(amount: float, armor_id: String, owned: bool, wound: String) -> float
```

Equipment-specific secondary wound resistance. Used only when the
server has confirmed a real infected hit against the wearer, and after
verifying the armor is still physically in their inventory.

### `weapon_damage`

```gdscript
static func weapon_damage(weapon_id: String) -> float
```

What a weapon does per hit. Fists when unarmed.

### `against_infected`

```gdscript
static func against_infected(damage: float, weapon_id: String, owned: bool) -> float
```

PvE-only equipment trait. The authoritative server calls this ONLY after
resolving a hit against a living infected, never for player-versus-player.

### `weapon_reach`

```gdscript
static func weapon_reach(weapon_id: String) -> float
```

Reach is configured by the carried weapon on the server.

### `ranged_range`

```gdscript
static func ranged_range(weapon_id: String) -> float
```

Ranged distance and noise are derived from carried gear on the server.

### `ranged_noise`

```gdscript
static func ranged_noise(weapon_id: String) -> Dictionary
```

### `weapon_cooldown`

```gdscript
static func weapon_cooldown(weapon_id: String) -> float
```

### `active_skill`

```gdscript
static func active_skill(weapon_id: String) -> Dictionary
```

Equipment determines the active ability. No class selection or client damage.
Ranged skills consume real server-owned ammunition in GameServer.cmd_skill.

### `crate_loot_bucket`

```gdscript
static func crate_loot_bucket(unit_roll: float) -> int
```

Deterministic weighted category for ordinary ruin-crate drops.
Weights reproduce the prior thresholds exactly (24/20/16/16/10/9/5).
A precomputed native Resource avoids one threshold chain per loot roll.
IMPORTANT: the caller always draws exactly one rng.randf(), regardless
of whether the custom engine is available; RNG/quantity order is stable.

### `crate_loot`

```gdscript
static func crate_loot(zone: int, rng: RandomNumberGenerator) -> Dictionary
```

Loot from a ruin crate or a dead zombie: {item_id: count}. Deterministic for a given rng.

### `zombie_loot`

```gdscript
static func zombie_loot(zombie_type: String, zone: int, rng: RandomNumberGenerator) -> Dictionary
```

