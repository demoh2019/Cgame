# road_network.gd

> Road graph between sites: Delaunay edges -> Kruskal minimum spanning tree plus a fraction of the remaining short edges as loops.

`res://scripts/shared/road_network.gd`

## Overview

Road graph between sites: Delaunay edges -> Kruskal minimum spanning tree
plus a fraction of the remaining short edges as loops.

Technique: the Delaunay-triangulation + MST + extra-edges road/dungeon
layout (e.g. the "Prim/Kruskal over Delaunay then re-add ~15% edges" recipe
from Vazgriz's dungeon generator write-up, itself after TinyKeep). Written
from the published algorithm description; no code copied. Kruskal with
union-find is textbook (Kruskal 1956). Triangulation uses Godot's
Geometry2D.triangulate_delaunay.
Reference: https://vazgriz.com/119/procedurally-generated-dungeons/ (idea only).

## Constants

- `const SAMPLE_STEP := 4.0`

## Functions

### `connect_sites`

```gdscript
static func connect_sites(sites: PackedVector2Array, extra_edge_ratio: float = 0.15, seed: int = 0) -> Array
```

Returns edges [{"a": int, "b": int, "length": float}]. The first n-1 entries
are the minimum spanning tree (acyclic, connects all sites); any further
entries are loop edges.

### `route_cost`

```gdscript
static func route_cost(a: Vector2, b: Vector2, height_at: Callable, slope_penalty: float) -> float
```

Travel cost of a straight road from a to b: length scaled up by slope.
height_at is Callable(Vector2) -> float. Each metre of climb adds
slope_penalty metres of effective length.

_7 private function(s) starting with `_` are not listed._
