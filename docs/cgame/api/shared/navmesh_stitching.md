# navmesh_stitching.gd

> Tiled navmesh stitching (portal links between tiles), polygon graph and A* + Simple Stupid Funnel path smoothing.

`res://scripts/shared/navmesh_stitching.gd`

## Overview

```text
Tiled navmesh stitching (portal links between tiles), polygon graph and
A* + Simple Stupid Funnel path smoothing.

Concepts ported from Recast/Detour tiled navmeshes (tile border portals,
polygon-corridor A*, string pulling):
  https://github.com/recastnavigation/recastnavigation
  Copyright (c) 2009-2010 Mikko Mononen, zlib license.
Funnel algorithm after Mikko Mononen's "Simple Stupid Funnel Algorithm"
write-up (https://digestingduck.blogspot.com/2010/03/simple-stupid-funnel-algorithm.html),
re-implemented from the description, as also done in Detour's
dtNavMeshQuery::findStraightPath. No GPL/LGPL code is used.

Tiles: {"origin": Vector2, "size": float, "polygons": Array[PackedVector2Array]}.
Orientation: travelling a -> b, "left" is the portal end with positive cross
product relative to the travel direction (+y when heading +x).
```

## Functions

### `stitch`

```gdscript
static func stitch(tile_a: Dictionary, tile_b: Dictionary, tolerance: float) -> Array
```

Finds polygon edges that lie on the border shared by two tiles and overlap
along it. Returns [{"poly_a": int, "poly_b": int, "left": Vector2, "right": Vector2}].

### `build_graph`

```gdscript
static func build_graph(tiles: Array, tolerance: float) -> Dictionary
```

Builds polygon adjacency across all tiles (intra-tile shared edges plus
stitched tile borders). Graph: {"polys": Array, "centers": PackedVector2Array,
"links": Array[Array[{to,left,right}]], "tile_of": PackedInt32Array, "offsets": PackedInt32Array}

### `find_path`

```gdscript
static func find_path(graph: Dictionary, start: Vector2, goal: Vector2) -> PackedVector2Array
```

A* over polygons (node position = entry portal midpoint) then funnel.

### `funnel`

```gdscript
static func funnel(portals: Array) -> PackedVector2Array
```

Simple Stupid Funnel. portals: Array of [left: Vector2, right: Vector2],
first = [start, start], last = [goal, goal].

_8 private function(s) starting with `_` are not listed._
