# elite_infected.gd

> (no header comment)

`res://scripts/shared/elite_infected.gd`

## Constants

- `const WorldGen = preload("res://scripts/shared/world_gen.gd")` - Deterministic elite encounters in dangerous ruins. Server owns eligibility, combat statistics and loot; none of these are sent as client commands.
- `const MIN_ZONE := 2`
- `const RARITY := 7`
- `const HEALTH_MULTIPLIER := 2.5`
- `const DAMAGE_MULTIPLIER := 1.4`
- `const MASTERY_XP_MULTIPLIER := 3`

## Functions

### `is_elite_spawn`

```gdscript
static func is_elite_spawn(spawn_id: int, zone: int, in_ruins: bool, seed: int) -> bool
```

### `empowered_stats`

```gdscript
static func empowered_stats(base: Dictionary) -> Dictionary
```

Important: duplicate the nested dictionary from Defs.ZOMBIES. Changing
class-wide zombie data would promote every infected in the simulation.

### `enhanced_loot`

```gdscript
static func enhanced_loot(normal_loot: Dictionary, zone: int) -> Dictionary
```

All loot is placed in the ordinary world loot bag (no instant transfer).
Loot from an ordinary infected is not mutated by this helper.

