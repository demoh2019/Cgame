# world_rivers.gd

> Rivers and lakes, generated once per world seed and shared by server and client.

`res://scripts/shared/world_rivers.gd`

## Overview

Rivers and lakes, generated once per world seed and shared by server and client.
Sources sit high in the hills; each river follows the steepest descent of the land (as rain
water would), its surface only ever going down, until it reaches the sea. A river that gets
trapped in a hollow fills it as a lake. The terrain is carved under them (a channel with
sloping banks), so height_at, movement and rendering all agree. Rivers are spline polylines
smoothed with Chaikin's algorithm and widen downstream.

## Constants

- `const Defs = preload("res://scripts/shared/defs.gd")`
- `const SOURCE_GRID := 380.0 # Candidate sources: one per grid cell, the highest sample.`
- `const SOURCE_MIN_HEIGHT := 26.0`
- `const MAX_RIVERS := 16`
- `const STEP := 22.0`
- `const MAX_STEPS := 140`
- `const MIN_LENGTH := 260.0`
- `const WIDTH_START := 2.2`
- `const WIDTH_END := 9.0`
- `const BANK := 11.0 # Sloping bank beyond the water's edge.`
- `const DEPTH := 1.25 # Water depth in mid channel.`
- `const MAX_GORGE := 22.0 # A river does not saw deeper than this through a ridge: it ends there.`
- `const CELL := 64.0`
- `const LAKE_MIN_RADIUS := 26.0`
- `const LAKE_MAX_RADIUS := 58.0`

## Functions

### `ensure_built`

```gdscript
func ensure_built() -> void
```

### `carve`

```gdscript
func carve(x: float, z: float, base: float) -> float
```

Ground with river channels and lake basins cut in (base = the natural land).

### `surface_at`

```gdscript
func surface_at(x: float, z: float) -> float
```

River or lake water surface over this point, or -INF when there is none.

### `segments_in_cell`

```gdscript
func segments_in_cell(cell: Vector2i) -> Array
```

### `lakes_in_cell`

```gdscript
func lakes_in_cell(cell: Vector2i) -> Array
```

_7 private function(s) starting with `_` are not listed._
