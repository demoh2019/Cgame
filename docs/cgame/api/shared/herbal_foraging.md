# herbal_foraging.gd

> Secondary, bounded medicinal foraging from genuine server-spawned plants.

`res://scripts/shared/herbal_foraging.gd`

## Overview

Secondary, bounded medicinal foraging from genuine server-spawned plants.
Only an actual completed gather may call roll(); no user-submitted loot
tables, professions or biome labels are accepted by the game server.

## Constants

- `const ITEM_ID := "wild_herbs"`
- `const FOREST_CHANCE := 0.24`
- `const SWAMP_CHANCE := 0.42`
- `const MIN_ZONE := 1`
- `const MAX_ZONE := 3`

## Functions

### `chance`

```gdscript
static func chance(kind: String, biome: String, zone: int) -> float
```

### `roll`

```gdscript
static func roll(kind: String, biome: String, zone: int, rng: RandomNumberGenerator) -> String
```

Called once when a depleted world plant actually yields its primary item.
Consumes no RNG draws if the world node is ineligible.

