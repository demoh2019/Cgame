# ambient_motes.gd

> Atmospheric detail without a particle simulator or per-mote draw calls.

`res://scripts/client/ambient_motes.gd`

## Overview

Atmospheric detail without a particle simulator or per-mote draw calls.
One 3x3 camera-local grid, one persistent GPU MultiMesh, and one shader.
Stable per-world-tile positions avoid popping while crossing chunk borders.

## Constants

- `const TILE_SIZE := 42.0`
- `const GRID_SIDE := 3`
- `const CELL_COUNT := GRID_SIDE * GRID_SIDE`
- `const MoteScreenSpace = preload("res://scripts/client/mote_screen_space.gd")`
- `const MAX_PER_TILE := 28`
- `const MAX_INSTANCES := CELL_COUNT * MAX_PER_TILE`
- `const UPDATE_INTERVAL := 0.25`
- `const TILE_CACHE_LIMIT := 18 # Recent tiles are reused when walking back.`
- `const PRESETS := [`

## Functions

### `profile`

```gdscript
static func profile(level: int) -> Dictionary
```

### `tile_seed`

```gdscript
static func tile_seed(cell: Vector2i) -> int
```

### `grid_cell`

```gdscript
static func grid_cell(world_position: Vector3) -> Vector2i
```

### `visibility`

```gdscript
static func visibility(biome: String, daylight: float, storm: float, level: int) -> Dictionary
```

Pure cinematic rules. Night forest/swamp fireflies; in warm, dry weather
sunlight catches pollen near the camera. Rain suppresses both effects.

### `setup`

```gdscript
func setup(world) -> void
```

### `update_view`

```gdscript
func update_view(center: Vector3, biome: String, daylight: float, storm: float, wind: Vector2, level: int, delta: float) -> void
```

One update per quarter-second; no per-mote CPU work while standing still.
The world input is the same height-map model the chunk streamer uses.

_4 private function(s) starting with `_` are not listed._
