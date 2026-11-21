# pcg_graphs.gd

> Code-built PCG graphs (engine module `pcg_graph`) for the world's dressing and for server-side loot/encounter spots.

`res://scripts/shared/pcg_graphs.gd`

## Overview

Code-built PCG graphs (engine module `pcg_graph`) for the world's dressing and for server-side loot/encounter spots.
Everything here is a pure builder: it returns a fresh PCGGraph resource (nodes, connections, exposed parameters) or
null when the running engine has no PCG classes, so the game still runs on stock Godot builds.

Graph parameters (override them through PCGContext/PCGComponent3D `overrides`): see the *_PARAMETERS of each builder.

## Constants

- `const CLASS_GRAPH := "PCGGraph"`
- `const CLASS_EXECUTOR := "PCGGraphExecutor"`
- `const LOOT_TIERS := 4` - Loot tiers produced by the loot graph (asset attribute value == tier).
- `const CLUTTER_BIOME_DENSITY := {"plains": 0.55, "forest": 1.0, "swamp": 0.8, "beach": 0.3, "mountain": 0.7}` - Per-biome density multipliers of the ground clutter (biomes of WorldGen.biome_at).
- `const ROADSIDE_PARAMETERS := {"spacing": 22.0, "lateral_offset": 3.2, "scale_min": 0.8, "scale_max": 1.2, "exclusion_margin": 6.0}` - Props along the road polylines (context user_data["roads"]), kept out of settlements (context exclusions). Asset attribute: 0 barrel, 1 crate, 2 basket, 3 bench, 4 stool.
- `const CLUTTER_PARAMETERS := {"spacing": 5.0, "jitter": 0.85, "noise_frequency": 0.03, "min_distance": 2.5, "max_slope": 32.0,` - Small rocks and stones scattered over the ground, denser by biome. Asset attribute: 0..3 rocks, 4..5 stones. Output carries a `cluster` attribute for HLOD grouping.
- `const DEBRIS_PARAMETERS := {"spacing": 6.0, "radius": 70.0, "min_distance": 4.0, "scale_min": 0.7, "scale_max": 1.3}` - Rubble, columns and stones around ruined cities (context user_data["ruins"] point list). Asset attribute: 0 large rubble, 1 half rubble, 2 column, 3 and 4 stones.
- `const LOOT_PARAMETERS := {"max_per_chunk": 3}` - Candidate cache spots (context user_data["pois"]: {position, density = tier / LOOT_TIERS}) become caches of loot tier 1..LOOT_TIERS (asset attribute); a spot never rolls a tier above its own density.
- `const ENCOUNTER_PARAMETERS := {"spacing": 24.0, "exclusion_margin": 40.0, "min_distance": 38.0, "max_per_chunk": 2}` - Where a roaming infected group may stand. The caller passes safe zones and settlements as context exclusions.

## Documented variables

- `static var simulate_missing := false` - Test switch: pretend the engine has no PCG classes.

## Functions

### `available`

```gdscript
static func available() -> bool
```

### `problems`

```gdscript
static func problems(graph) -> PackedStringArray
```

Problems of a graph: empty when it is sound (no cycle, no dangling connection or parameter binding).

### `roadside_dressing`

```gdscript
static func roadside_dressing()
```

### `biome_clutter`

```gdscript
static func biome_clutter()
```

### `ruin_debris`

```gdscript
static func ruin_debris()
```

### `loot_caches`

```gdscript
static func loot_caches()
```

### `encounter_spots`

```gdscript
static func encounter_spots()
```

### `all_builders`

```gdscript
static func all_builders() -> Dictionary
```

Every builder by name, for tests and tooling.

_3 private function(s) starting with `_` are not listed._
