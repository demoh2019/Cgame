# pcg_world_dressing.gd

> Cosmetic world dressing from the engine's PCG graphs: roadside props, biome ground clutter and ruin debris.

`res://scripts/client/pcg_world_dressing.gd`

## Overview

Cosmetic world dressing from the engine's PCG graphs: roadside props, biome ground clutter and ruin debris. One
PCGComponent3D per graph streams 64 m cells around the player and draws them as MultiMesh instances with a visibility
range. Purely client-side and cosmetic: no gameplay depends on it (loot and encounters are server-side, see
scripts/server/pcg_spawns.gd). Does nothing on engines without the PCG classes or on the Performance quality tier.

## Constants

- `const Defs = preload("res://scripts/shared/defs.gd")`
- `const PcgGraphs = preload("res://scripts/shared/pcg_graphs.gd")`
- `const ModelCatalog = preload("res://scripts/client/model_catalog.gd")`
- `const GraphicsQuality = preload("res://scripts/client/graphics_quality.gd")`
- `const WorldRoads = preload("res://scripts/shared/world_roads.gd")`
- `const CELL_SIZE := 64.0`
- `const SETTLEMENT_KINDS := ["village", "farm", "outpost", "camp", "dock", "lighthouse", "tower"]`
- `const REGION_REACH := 13 # Regions -13..12 on both axes: the whole island (as WorldRoads).`
- `const HUB_CLEARANCE := 25.0 # Added to the hub's safe radius: no clutter on the plaza.`
- `const ASYNC_CELLS := true` - The world's terrain functions are not thread-safe (cached region state), so the component bakes height, water and biome into grids on the main thread (BAKE_STEP metres) and the graph then runs on the worker pool reading only the grids. Engines without baking (older pcg_graph) fall back to main-thread cells.
- `const BAKE_STEP := 2.0`
- `const CACHE_DIR := "user://pcg_cache"` - Finished cells are written to disk and reloaded on the next run instead of regenerating. Bump CACHE_VERSION whenever world generation (heights, biomes, roads) or the graphs change meaning without changing their parameters.
- `const CACHE_VERSION := 1`
- `const REPOSITION_STEP := 8.0 # The streaming anchor follows the player in steps, not every frame.`
- `const LEVEL_POLL_SECONDS := 2.0`
- `const TIERS := [` - Budgets per GraphicsQuality level (0 Performance ... 3 Ultra). Level 0 draws nothing. radius: streaming radius in 64 m cells; range: visibility_range_end; spacing: lattice spacing override per graph.

## Documented variables

- `static var debug_draw := false` - Runtime PCG debugging: crosses at every generated point, coloured by asset (toggle with set_debug_draw).

## Functions

### `budget`

```gdscript
static func budget(level: int) -> Dictionary
```

The budget of a quality level ({} = off). Pure: also used by tests.

### `setup`

```gdscript
func setup(p_world) -> bool
```

### `update`

```gdscript
func update(position: Vector3, delta: float = 0.0) -> void
```

Position of the player; call every frame (cheap): moves the streaming anchor and re-reads the quality level now and then.

### `component_names`

```gdscript
func component_names() -> Array
```

### `build_user_data`

```gdscript
static func build_user_data(p_world) -> Dictionary
```

Road polylines ("roads") and ruined-city centres ("ruins") as PCG user data.

### `build_exclusions`

```gdscript
static func build_exclusions(p_world) -> Array
```

Hub plaza and settlements as exclusion cylinders.

### `set_debug_draw`

```gdscript
func set_debug_draw(enabled: bool) -> void
```

Shows or hides the PCG debug points on every dressing component (regenerates the loaded cells).

_7 private function(s) starting with `_` are not listed._
