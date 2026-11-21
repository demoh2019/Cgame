# navmesh_carving.gd

> Dynamic navmesh obstacle carving with a budgeted tile cache.

`res://scripts/shared/navmesh_carving.gd`

## Overview

Dynamic navmesh obstacle carving with a budgeted tile cache.

Concepts ported from Recast & Detour (DetourTileCache: obstacles queued per
tile, tiles rebuilt incrementally under a per-update budget, rebuilt tiles
re-linked to neighbours) and from Mikko Mononen's "simple stupid funnel"
string pulling (DetourNavMeshQuery::findStraightPath).
Recast Navigation, Copyright (c) 2009-2010 Mikko Mononen, zlib license.
This is an independent 2D GDScript implementation, not a line-by-line copy.
Polygon clipping/decomposition uses Godot's Geometry2D (MIT).

Walkable space is a grid of tiles; each tile holds convex polygons.
Obstacles (polygons or circles, grown by the agent radius) are subtracted
from the tiles they touch. Destroying an obstacle (barricade, wall) re-carves
only those tiles, reopening routes, and reports them in the change events so
AI can repath.

## Constants

- `const EPS := 0.002`

## Functions

### `setup`

```gdscript
func setup(p_bounds: Rect2, p_tile_size: float, p_agent_radius: float) -> void
```

### `set_walkable`

```gdscript
func set_walkable(polys: Array) -> void
```

Restrict walkable space to the given polygons (clipped into tiles).

### `add_obstacle`

```gdscript
func add_obstacle(id: Variant, shape: Variant) -> void
```

shape: PackedVector2Array polygon, or {center: Vector2, radius: float, segments: int}.

### `remove_obstacle`

```gdscript
func remove_obstacle(id: Variant) -> bool
```

### `on_destroyed`

```gdscript
func on_destroyed(id: Variant) -> bool
```

Destruction hook: a broken barricade/wall stops blocking the navmesh.

### `has_obstacle`

```gdscript
func has_obstacle(id: Variant) -> bool
```

### `pending_tiles`

```gdscript
func pending_tiles() -> int
```

### `update`

```gdscript
func update(max_tiles_per_call: int = 4) -> int
```

Re-carves up to max_tiles_per_call dirty tiles (<= 0 means all). Returns tiles rebuilt.

### `consume_changed_tiles`

```gdscript
func consume_changed_tiles() -> Array[Vector2i]
```

Tiles rebuilt since the last call (AI repath notifications).

### `tile_version`

```gdscript
func tile_version(tile: Vector2i) -> int
```

### `tile_count`

```gdscript
func tile_count() -> Vector2i
```

### `tile_of`

```gdscript
func tile_of(point: Vector2) -> Vector2i
```

### `polygons_in_tile`

```gdscript
func polygons_in_tile(tile: Vector2i) -> Array[PackedVector2Array]
```

### `is_walkable`

```gdscript
func is_walkable(point: Vector2) -> bool
```

### `is_convex`

```gdscript
static func is_convex(poly: PackedVector2Array) -> bool
```

### `find_path`

```gdscript
func find_path(from: Vector2, to: Vector2) -> PackedVector2Array
```

A* over polygons, then funnel string pulling. Empty when either end is blocked or unreachable.

### `path_affected`

```gdscript
func path_affected(path: PackedVector2Array, changed: Array[Vector2i]) -> bool
```

True when any segment of the path passes through one of the changed tiles.

_19 private function(s) starting with `_` are not listed._
