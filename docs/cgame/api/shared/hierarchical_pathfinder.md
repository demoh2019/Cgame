# hierarchical_pathfinder.gd

> HPA*-style hierarchical pathfinding over a walkability grid for large streamed regions.

`res://scripts/shared/hierarchical_pathfinder.gd`

## Overview

HPA*-style hierarchical pathfinding over a walkability grid for large streamed regions.
Inspired by Botea et al., "Near Optimal Hierarchical Path-Finding" (HPA*): the grid is cut
into square clusters, entrance nodes are placed on shared cluster borders, and an abstract
graph is searched with A* before the route is refined to grid cells.

Grid movement is 4-connected (every step is one cell up, down, left or right, cost 1).
Paths are valid but not guaranteed to be the globally shortest (classic HPA* trade-off).
Dynamic obstacles: change what `walkable` returns, then call invalidate_cluster() for each
affected cell; only that cluster and its borders are rebuilt.

## Constants

- `const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]`
- `const LONG_RUN := 6` - Border runs longer than this get extra entrance nodes at both ends (HPA* entrance rule).
- `const FAR := 1 << 30`

## Classes

- `class _Heap:`

## Documented variables

- `var cache_hits: int = 0` - Abstract-route reuses (same start/goal cluster pair).

## Functions

### `build`

```gdscript
func build(w: int, h: int, cluster: int, walkable: Callable) -> void
```

Builds clusters, entrance nodes and the abstract graph. walkable.call(x, y) -> bool.

### `find_path`

```gdscript
func find_path(start: Vector2i, goal: Vector2i) -> PackedVector2Array
```

Finds a 4-connected path of grid cells (start and goal included); empty when unreachable.

### `invalidate_cluster`

```gdscript
func invalidate_cluster(cell: Vector2i) -> void
```

Rebuilds only the cluster containing `cell` (and its border entrances) after the
walkability of cells inside it changed.

### `node_count`

```gdscript
func node_count() -> int
```

Number of live abstract nodes (for tests and debug overlays).

_17 private function(s) starting with `_` are not listed._
