# defs.gd

> Static game data shared by the server and the client: items, recipes, zones and tuning numbers.

`res://scripts/shared/defs.gd`

## Overview

Static game data shared by the server and the client: items, recipes, zones and tuning numbers.
Everything here is plain data and pure functions, so it can be unit tested without a scene.

## Constants

- `const CHUNK_SIZE := 64.0`
- `const WATER_LEVEL := 0.0`
- `const TICK_RATE := 20 # Server simulation ticks per second.`
- `const SNAPSHOT_RATE := 10 # Snapshots per second.`
- `const INTEREST_RADIUS := 90.0 # Entities farther than this from a player are not sent to them.`
- `const HUB_SAFE_RADIUS := 45.0 # Nobody can be hurt inside it.`
- `const ZONE_RADII := [260.0, 620.0, 1050.0] # Green ends at 260 m, yellow at 620 m, red at 1050 m, then black.`
- `const ZONE_NAMES := ["green", "yellow", "red", "black"]`
- `const MAX_TIER := 8 # T1-T3 in green/yellow/red, T4-T8 deeper and deeper into the black zone.`
- `const CAMP_FISH_STEW := "camp_fish_stew" # Clean fish-and-water camp meal.`
- `const WALK_SPEED := 4.2`
- `const SPRINT_SPEED := 6.6`
- `const PLAYER_RADIUS := 0.45`
- `const REACH := 2.6 # Gathering / looting distance.`
- `const MELEE_RANGE := 2.2`
- `const PISTOL_RANGE := 40.0`
- `const MAX_HEALTH := 100.0`
- `const INFECTION_MAX := 100.0`
- `const INFECTION_GROWTH_PER_SECOND := 0.065`
- `const INFECTION_DAMAGE_START := 30.0`
- `const INFECTION_DAMAGE_PER_SECOND := 1.4`
- `const ZOMBIE_INFECTION_PER_HIT := {"walker": 8.0, "runner": 12.0, "brute": 20.0, "spitter": 10.0,`
- `const BLEEDING_MAX := 100.0`
- `const BLEEDING_DAMAGE_PER_SECOND := 1.2`
- `const BLEEDING_DECAY_PER_SECOND := 0.2`
- `const ZOMBIE_BLEEDING_PER_HIT := {"walker": 9.0, "runner": 13.0, "brute": 22.0, "spitter": 3.0,`
- `const PVP_MELEE_BLEEDING_PER_HIT := 12.0`
- `const FRACTURE_MAX := 100.0`
- `const FRACTURE_DECAY_PER_SECOND := 0.04`
- `const FRACTURE_SPEED_FACTOR := 0.65`
- `const ZOMBIE_FRACTURE_PER_HIT := {"brute": 35.0, "sentinel": 18.0}`
- `const COMBAT_ENERGY_MAX := 100.0`
- `const COMBAT_ENERGY_REGEN := 9.0`
- `const MAX_STAMINA := 100.0`
- `const SPRINT_STAMINA_PER_SECOND := 18.0`
- `const STAMINA_REGEN_PER_SECOND := 11.0`
- `const STAMINA_RECOVERY_DELAY := 0.8`
- `const HUNGER_PER_SECOND := 0.045`
- `const THIRST_PER_SECOND := 0.07`
- `const STARVE_DAMAGE_PER_SECOND := 1.2`
- `const SPRINT_NOISE_RADIUS := 21.0`
- `const SPRINT_NOISE_SECONDS := 0.8`
- `const GUNSHOT_NOISE_RADIUS := 32.0`
- `const GUNSHOT_NOISE_SECONDS := 3.0`
- `const INVENTORY_SLOTS := 24`
- `const CARRY_COMFORT_KG := 35.0`
- `const CARRY_HEAVY_KG := 90.0`
- `const CARRY_MIN_SPEED_FACTOR := 0.5`
- `const ITEM_KIND_WEIGHT := {`
- `const STASH_SLOTS := 48 # Account-bound safe-settlement storage; never dropped on death.`
- `const RESPAWN_SECONDS := 4.0`
- `const THERMAL_WRAP_SECONDS := 180.0`
- `const THERMAL_WRAP_REDUCTION := 0.70`
- `const ZOMBIES := {`
- `const QUALITY_NAMES := ["", "Normal", "Good", "Outstanding", "Excellent", "Masterpiece"]`
- `const MAX_QUALITY := 5`
- `const QUALITY_KINDS := ["weapon", "armor", "tool"]`
- `const BLACK_TIER_STEP := 450.0` - Resource tier at a distance from the hub: the black zone keeps getting richer outward.
- `const MAX_ENCHANT := 3`
- `const ENCHANT_KINDS := ["weapon", "armor", "head", "cape", "hands", "feet", "tool"]`
- `const ENCHANT_STAT_BONUS := 0.10 # +10% damage / protection per enchant level.`
- `const ENCHANT_MATERIALS := ["", "rune", "soul", "relic"] # Material to reach .1 / .2 / .3.`

## Functions

### `items`

```gdscript
static func items() -> Dictionary
```

### `recipes`

```gdscript
static func recipes() -> Dictionary
```

### `item`

```gdscript
static func item(id: String) -> Dictionary
```

### `is_item`

```gdscript
static func is_item(id: String) -> bool
```

### `base_id`

```gdscript
static func base_id(id: String) -> String
```

### `quality_of`

```gdscript
static func quality_of(id: String) -> int
```

### `with_quality`

```gdscript
static func with_quality(id: String, quality: int) -> String
```

### `can_have_quality`

```gdscript
static func can_have_quality(id: String) -> bool
```

### `roll_quality`

```gdscript
static func roll_quality(rng: RandomNumberGenerator, skill_bonus: float = 0.0) -> int
```

Crafting quality roll: skill and luck push toward Masterpiece. Returns 1..5.

### `stack_size`

```gdscript
static func stack_size(id: String) -> int
```

### `item_weight`

```gdscript
static func item_weight(id: String) -> float
```

### `carry_speed_factor`

```gdscript
static func carry_speed_factor(weight_kg: float) -> float
```

### `tier_of`

```gdscript
static func tier_of(id: String) -> int
```

### `tier_for_distance`

```gdscript
static func tier_for_distance(distance: float) -> int
```

### `zone_index_for_distance`

```gdscript
static func zone_index_for_distance(distance: float) -> int
```

### `tool_tier_for_node`

```gdscript
static func tool_tier_for_node(kind: String) -> String
```

### `node_info`

```gdscript
static func node_info(kind: String) -> Dictionary
```

### `enchanted_id`

```gdscript
static func enchanted_id(base: String, level: int) -> String
```

"club_2" + 1 -> "club_2@1"; level 0 is the base item.

### `unenchanted_id`

```gdscript
static func unenchanted_id(id: String) -> String
```

The unenchanted item an id belongs to ("club_2@3" -> "club_2").

### `enchant_of`

```gdscript
static func enchant_of(id: String) -> int
```

### `item_power`

```gdscript
static func item_power(id: String) -> int
```

Albion item power: 300 + 100 per tier + 100 per enchantment level (T4.1 = 800),
plus the quality bonus (Good +20, Outstanding +40, Excellent +60, Masterpiece +100).

### `enchant_cost`

```gdscript
static func enchant_cost(id: String) -> Dictionary
```

What enchanting `id` one level further costs: {material: count, "silver": n}, or {} if it cannot be enchanted.

_5 private function(s) starting with `_` are not listed._
