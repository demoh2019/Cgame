# world_gen.gd

> Deterministic world from a seed: terrain height, biomes, zones and what lies in every chunk.

`res://scripts/shared/world_gen.gd`

## Overview

Deterministic world from a seed: terrain height, biomes, zones and what lies in every chunk.
The server and every client build the same world from the same seed, so the world never has to
be sent over the network, only what changes in it.

## Constants

- `const WorldRivers = preload("res://scripts/shared/world_rivers.gd")`
- `const Defs = preload("res://scripts/shared/defs.gd")`
- `const Dungeon = preload("res://scripts/shared/dungeon.gd")`
- `const WorldPoi = preload("res://scripts/shared/world_poi.gd")`
- `const WorldRoads = preload("res://scripts/shared/world_roads.gd")`
- `const CACHE_LIMIT := 256`
- `const HUB_HEIGHT := 3.0`
- `const HUB_BLEND_END := 140.0`
- `const LAND_BIAS := 8.0 # Raises all land: with 0 only a tenth of the island could be walked to from the hub.`
- `const WORLD_RADIUS := 3200.0`
- `const EDGE_START := 2650.0`
- `const AREA_ADJECTIVES := ["Whispering", "Silent", "Broken", "Hollow", "Ashen", "Gilded", "Lonely", "Frozen", "Burning", "Forgotten", "Wailing", "Emerald", "C...`
- `const AREA_NOUNS := {`
- `const BUILDING_VARIANTS := 5 # building-small-a..d and the garage.`
- `const BUILDING_SCALE := 6.0`
- `const WALL_SCALE := 3.0`
- `const SUNKEN_MIN_DEPTH := 2.2` - Sunken caches lie on the bottom of deep water; only a diver can open them. A separate random stream keeps every other piece of the chunk exactly as it was before.
- `const SUNKEN_ID_BASE := 950`
- `const HOSTILE_ID_BASE := 900` - Extra infected that make the wilds teem: ruin guardians and screamers, crawler swarms, lone stalkers that hunt you down, and stragglers even in the green zone. Own random stream, so every other piece of the chunk is unchanged.
- `const HOSTILE_ID_MAX := 45`
- `const OUTPOST_ID_BASE := 850` - Lone wilderness outposts between the settlements: a trapper's shack, a watchtower, or a cluster of ruins, often with a loot crate and some clutter. Collidable structures shared by server and client; own random stream (ids 850-899), so everything else in the chunk keeps its place.
- `const OUTPOST_CHANCE := 0.32`
- `const GROVE_ID_BASE := 960` - Extra trees in groves, so forests read as forests: a few grove centres per chunk with trees clustered around them, densest in forest, thinner in swamp and plains. Real gatherable, collidable tree nodes (server and client agree), on their own random stream so every other node of the chunk keeps its place. Ids 960-999.
- `const GROVE_ID_MAX := 40`
- `const GROVE_TREES := {"forest": [18, 30], "swamp": [8, 14], "plains": [4, 10]}`

## Documented variables

- `var _structure_parts: Dictionary = {}` - A structure made of several circles (house walls, doorways). Tagged so house placement can tell pieces apart from scenery; removed together by remove_dynamic_blocker(id).

## Functions

### `road_coverage_at`

```gdscript
func road_coverage_at(x: float, z: float) -> float
```

Renderer and authoritative locomotion query exactly the same road graph.

### `mix`

```gdscript
static func mix(a: int, b: int, c: int, d: int = 0) -> int
```

### `height_at`

```gdscript
func height_at(x: float, z: float) -> float
```

Terrain height: the natural land, levelled under every site so buildings stand on flat ground.

### `ground_at`

```gdscript
func ground_at(x: float, z: float) -> float
```

The ground itself (no bridge decks): what the terrain mesh is built from.

### `is_water`

```gdscript
func is_water(x: float, z: float) -> bool
```

### `water_level_at`

```gdscript
func water_level_at(x: float, z: float) -> float
```

Water surface height here: the sea level, or a river/lake surface above it.

### `normal_at`

```gdscript
func normal_at(x: float, z: float) -> Vector3
```

### `biome_at`

```gdscript
func biome_at(x: float, z: float) -> String
```

### `biomes_at_points`

```gdscript
func biomes_at_points(points: PackedVector2Array, heights: PackedFloat64Array) -> PackedStringArray
```

Batch biome classification for render/chart consumers with precomputed heights.
Scalar biome_at() remains the authoritative query and is not changed for simulation.

### `area_name`

```gdscript
func area_name(x: float, z: float) -> String
```

### `zone_at`

```gdscript
func zone_at(x: float, z: float) -> int
```

### `dungeon_zone`

```gdscript
func dungeon_zone(region: Vector2i) -> int
```

A dungeon is one zone deeper than the land above it (harder infected, richer chests), at most black.

### `dungeon_bunker`

```gdscript
func dungeon_bunker(region: Vector2i) -> Dictionary
```

The bunker above a region's dungeon, or {} where that region has none.

### `tier_for_zone`

```gdscript
static func tier_for_zone(zone: int) -> int
```

### `settlement_station_near`

```gdscript
func settlement_station_near(x: float, z: float, reach: float = WorldPoi.STATION_RANGE) -> bool
```

A workbench station of a settlement within reach (the hub's own workbench is separate, see GameServer).

### `is_safe`

```gdscript
func is_safe(x: float, z: float) -> bool
```

### `hub_structures`

```gdscript
func hub_structures() -> Array
```

Everything built in the hub: a fountain plaza, a ring of houses and the workbench.

### `cell_of`

```gdscript
static func cell_of(x: float, z: float) -> Vector2i
```

### `cell_origin`

```gdscript
static func cell_origin(cell: Vector2i) -> Vector2
```

### `entity_id`

```gdscript
static func entity_id(cell: Vector2i, index: int) -> int
```

Built from the cell coordinates, so two chunks can never share an id (a hash would, now and then, and a depleted tree
would hide another one far away). Cells within +-1024 of the origin, 65 km, fit; ids stay under 4.3e9, clear of the
server's own running ids and the barricade ids.

### `chunk`

```gdscript
func chunk(cell: Vector2i) -> Dictionary
```

Everything in a chunk, derived from the seed: gatherable nodes, ruins with loot crates and the
places where zombies spawn. The same call always gives the same answer.

### `add_dynamic_blocker`

```gdscript
func add_dynamic_blocker(id: int, x: float, z: float, radius: float) -> void
```

Static things that block movement near a point, for both the server and client prediction.

### `add_structure_blockers`

```gdscript
func add_structure_blockers(id: int, circles: Array) -> void
```

### `remove_dynamic_blocker`

```gdscript
func remove_dynamic_blocker(id: int) -> void
```

### `blockers_near`

```gdscript
func blockers_near(x: float, z: float, radius: float) -> Array
```

_16 private function(s) starting with `_` are not listed._
