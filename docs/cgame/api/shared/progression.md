# progression.gd

> Server-owned, classless gathering and crafting progression.

`res://scripts/shared/progression.gd`

## Overview

Server-owned, classless gathering and crafting progression.
Persistent skills survive character death; access checks are authoritative.

## Constants

- `const Defs = preload("res://scripts/shared/defs.gd")`
- `const Scavenging = preload("res://scripts/shared/scavenging.gd")`
- `const XP_PER_LEVEL := 100`
- `const MAX_XP := 100000000`
- `const GATHER_XP_PER_ITEM := 8`
- `const CRAFT_XP_PER_BATCH := 25`
- `const GATHER_SKILLS := ["wood", "stone", "ore", "fiber", "fishing"]`
- `const COMBAT_SKILLS := ["melee", "ranged"]`
- `const COMBAT_XP_PER_LEVEL := 80`
- `const COMBAT_MAX_LEVEL := 5`
- `const COMBAT_DAMAGE_PER_LEVEL := 0.03`
- `const MASTERY_MAX_LEVEL := 100`
- `const MASTERY_FAME_SCALE := 20.0 # level = sqrt(fame / 20): L10 = 2k fame, L100 = 200k fame.`
- `const MASTERY_IP_PER_LEVEL := 2 # Albion: specialization raises the item power of that line.`
- `const MASTERY_ULTIMATE_PER_LEVEL := 0.002 # Weapon ultimate (E) scales with line mastery.`

## Functions

### `resource_skill`

```gdscript
static func resource_skill(kind: String) -> String
```

### `level_for_xp`

```gdscript
static func level_for_xp(xp: int) -> int
```

### `gathering_level`

```gdscript
func gathering_level(kind: String) -> int
```

### `crafting_level`

```gdscript
func crafting_level() -> int
```

### `can_gather`

```gdscript
func can_gather(kind: String, tier: int) -> bool
```

### `can_craft_tier`

```gdscript
func can_craft_tier(tier: int) -> bool
```

### `award_gather`

```gdscript
func award_gather(kind: String, tier: int, quantity: int) -> int
```

### `award_craft`

```gdscript
func award_craft(tier: int, batches: int) -> int
```

### `combat_skill_for_weapon`

```gdscript
static func combat_skill_for_weapon(weapon_id: String) -> String
```

### `combat_level`

```gdscript
func combat_level(skill: String) -> int
```

### `combat_levels`

```gdscript
func combat_levels() -> Dictionary
```

### `combat_damage_multiplier`

```gdscript
func combat_damage_multiplier(weapon_id: String) -> float
```

### `award_combat`

```gdscript
func award_combat(weapon_id: String, earned_xp: int) -> int
```

### `scavenging_level`

```gdscript
func scavenging_level() -> int
```

### `award_scavenge`

```gdscript
func award_scavenge(zone: int) -> int
```

### `levels`

```gdscript
func levels() -> Dictionary
```

### `to_dict`

```gdscript
func to_dict() -> Dictionary
```

### `load_dict`

```gdscript
func load_dict(data: Variant) -> bool
```

Atomic validation: invalid or client-forged data cannot replace live skill XP.

### `weapon_family`

```gdscript
static func weapon_family(weapon_id: String) -> String
```

Weapon line of an item: "spear_3@2+4" -> "spear"; "pistol" -> "pistol". "" for non-weapons.

### `mastery_level_for_fame`

```gdscript
static func mastery_level_for_fame(fame: int) -> int
```

### `weapon_mastery_level`

```gdscript
func weapon_mastery_level(weapon_id: String) -> int
```

### `load_weapon_fame`

```gdscript
func load_weapon_fame(raw: Variant) -> void
```

Restores saved mastery; malformed entries are skipped (older saves have none).

### `mastery_item_power`

```gdscript
func mastery_item_power(weapon_id: String) -> int
```

Extra item power from mastering this weapon's line (+2 IP per level, +200 at L100).

### `mastery_ultimate_multiplier`

```gdscript
func mastery_ultimate_multiplier(weapon_id: String) -> float
```

Multiplier for the weapon ultimate's damage from line mastery (up to +20%).

_1 private function(s) starting with `_` are not listed._
