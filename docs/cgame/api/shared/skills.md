# skills.gd

> The skill tree: every kind of action trains its own skill, levels give passive bonuses, and every level also gives a skill point to spend on perks in that sk...

`res://scripts/shared/skills.gd`

## Overview

```text
The skill tree: every kind of action trains its own skill, levels give passive bonuses, and every level
also gives a skill point to spend on perks in that skill's branch. Server-owned and persisted; nothing
here trusts a client: levels come from XP, perks are bought with points the XP earned.

Branches and skills
  Gathering : woodcutting, mining, foraging
  Combat    : melee, marksman, slayer (zombie kills), toughness (damage taken)
  Survival  : athletics (running), survivalist (eating and drinking), medic (healing)
  Craft     : crafting, scavenging (searching crates and bags)
  Explorer  : explorer (distance and new regions)
Bonus names (see BONUS_CAPS) are plain numbers the rest of the game asks for with `bonus("name")`.
```

## Constants

- `const MAX_LEVEL := 50`
- `const XP_BASE := 40.0`
- `const XP_EXPONENT := 1.55`
- `const MAX_XP := 400000`
- `const SAVE_VERSION := 1`
- `const BRANCHES := {`
- `const SKILLS := {`
- `const BONUS_CAPS := {`
- `const MAX_HEALTH_BONUS := 100.0 # Same as BONUS_CAPS["max_health"]; used for save validation.`
- `const PERKS := {`
- `enum Buy { OK, UNKNOWN, MAX_RANK, LEVEL, REQUIRES, POINTS }`

## Functions

### `reset`

```gdscript
func reset() -> void
```

### `xp_to_next`

```gdscript
static func xp_to_next(level: int) -> int
```

XP needed to advance from `level` to the next one.

### `xp_for_level`

```gdscript
static func xp_for_level(level: int) -> int
```

Total XP at which a skill reaches `level` (level 1 needs none).

### `level_for_xp`

```gdscript
static func level_for_xp(amount: int) -> int
```

### `level`

```gdscript
func level(skill: String) -> int
```

### `total_level`

```gdscript
func total_level() -> int
```

### `progress`

```gdscript
func progress(skill: String) -> float
```

0..1 progress to the next level.

### `points_earned`

```gdscript
func points_earned() -> int
```

One point for every level gained in any skill.

### `perk_cost_of`

```gdscript
static func perk_cost_of(perk_id: String, rank_count: int) -> int
```

### `points_spent`

```gdscript
func points_spent() -> int
```

### `points_available`

```gdscript
func points_available() -> int
```

### `rank`

```gdscript
func rank(perk_id: String) -> int
```

### `next_rank_requirement`

```gdscript
func next_rank_requirement(perk_id: String) -> Dictionary
```

What the next rank of a perk needs, or {} when it is maxed. Used by the interface and by `buy_perk`.

### `buy_perk`

```gdscript
func buy_perk(perk_id: String) -> int
```

### `bonus`

```gdscript
func bonus(name: String) -> float
```

The total of a named bonus from passives and perks, never above its cap. 0 for unknown names.

### `all_bonuses`

```gdscript
func all_bonuses() -> Dictionary
```

All non-zero bonuses, for the interface.

### `add_xp`

```gdscript
func add_xp(skill: String, amount: float) -> Dictionary
```

Adds XP to a skill (the explorer's xp_gain bonus applies). Returns {"gained": int, "levels": [new levels]}.

### `skill_for_node`

```gdscript
static func skill_for_node(kind: String) -> String
```

Which skill a gatherable node trains.

### `to_dict`

```gdscript
func to_dict() -> Dictionary
```

### `load_dict`

```gdscript
func load_dict(data: Variant) -> bool
```

Atomic: returns false and changes nothing unless the data is fully consistent. Perks must be affordable with
the points the XP earned, meet their level and prerequisite rules, and no unknown skill or perk may appear.

### `describe_bonus`

```gdscript
static func describe_bonus(name: String, value: float) -> String
```

A one-line text for a bonus, for the interface and tests.

_2 private function(s) starting with `_` are not listed._
