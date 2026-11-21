# pcg_spawns.gd

> PCG-placed loot caches and encounter spots, added per chunk on top of WorldGen's own content.

`res://scripts/server/pcg_spawns.gd`

## Overview

PCG-placed loot caches and encounter spots, added per chunk on top of WorldGen's own content.

Deterministic: the engine's PCG graphs are seeded by the world seed and never depend on how the world is cut into
chunks, and the candidate lists are pure functions of the world seed. The server is authoritative (it alone decides what
a crate holds and when an infected group spawns); clients attach the same extender only so their view of the chunk
lists the same crates. No-op when ENABLED is false or the engine has no PCG classes: chunks are then exactly the
classic ones. Hook: WorldGen.spawn_extender, called at the end of chunk generation (see PcgSpawns.attach).

## Constants

- `const Defs = preload("res://scripts/shared/defs.gd")`
- `const Dungeon = preload("res://scripts/shared/dungeon.gd")`
- `const PcgGraphs = preload("res://scripts/shared/pcg_graphs.gd")`
- `const ENABLED := true`
- `const CRATE_ID_BASE := 700`
- `const CRATE_ID_MAX := 12`
- `const SPAWN_ID_BASE := 720`
- `const SPAWN_ID_MAX := 24`
- `const MAX_CACHES_PER_CHUNK := 3`
- `const MAX_ENCOUNTER_SPAWNS_PER_CHUNK := 8`
- `const LOOT_KINDS := ["city", "bunker", "depot", "mine", "landmark"]`
- `const SETTLEMENT_KINDS := ["village", "farm", "outpost", "camp", "dock", "lighthouse", "tower"]`
- `const SPOTS_PER_SITE := 4`
- `const RUIN_SPOTS := 3`
- `const HUB_ENCOUNTER_RADIUS := 25.0 # Added to Defs.HUB_SAFE_RADIUS before the graph's own margin.`
- `const ENCOUNTERS_PER_ZONE := [1, 1, 2, 2]`
- `const CRATE_VARIANTS := 6`

## Functions

### `attach`

```gdscript
static func attach(p_world) -> bool
```

Hooks an extender into a world when the engine supports it; returns whether it is active.

### `active`

```gdscript
func active() -> bool
```

### `extend`

```gdscript
func extend(cell: Vector2i, data: Dictionary) -> void
```

Adds the PCG crates and infected spawns of a chunk to its data (called by WorldGen at the end of generation).

### `run_graph`

```gdscript
func run_graph(graph, bounds: AABB, cell: Vector2i, overrides: Dictionary, exclusions: Array, user_data: Dictionary, salt: int)
```

The points of a graph over a chunk, or null on failure.

### `safe_exclusions`

```gdscript
func safe_exclusions(center: Vector2, reach: float) -> Array
```

Exclusion cylinders around a chunk: the hub's safe zone and every settlement that can reach it.

_6 private function(s) starting with `_` are not listed._
