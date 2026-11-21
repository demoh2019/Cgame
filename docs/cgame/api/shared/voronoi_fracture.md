# voronoi_fracture.gd

> Voronoi fracture of a box into convex cells (Geometry Collection / Chaos style).

`res://scripts/shared/voronoi_fracture.gd`

## Overview

Voronoi fracture of a box into convex cells (Geometry Collection / Chaos style).

Method: each cell is the intersection of the box's six half-spaces with one
perpendicular-bisector half-space per other site (convex polyhedron clipping).
This is the classic Voronoi-cell construction (Aurenhammer, "Voronoi diagrams",
ACM Computing Surveys 1991); vertices come from Godot's own plane intersection
(Geometry3D.compute_convex_mesh_points) and the hull is triangulated by a small
original brute-force routine. No third-party code is copied.

## Constants

- `const EPS := 1e-4`

## Functions

### `fracture_box`

```gdscript
static func fracture_box(size: Vector3, sites: PackedVector3Array) -> Array
```

One convex cell per site, as hull points. The box is centred at the origin.
A site whose cell is empty (coincident with another) yields an empty array.

### `random_sites`

```gdscript
static func random_sites(size: Vector3, count: int, seed: int, impact: Vector3 = Vector3.INF, impact_bias: float = 0.0) -> PackedVector3Array
```

Sites inside the box (centred at origin); clustered near `impact` when given.

### `cell_volume`

```gdscript
static func cell_volume(points: PackedVector3Array) -> float
```

### `centroid`

```gdscript
static func centroid(points: PackedVector3Array) -> Vector3
```

### `hull_triangles`

```gdscript
static func hull_triangles(points: PackedVector3Array) -> PackedVector3Array
```

Triangulated convex hull (flat triangle list, counter-clockwise seen from outside).
Brute force over point triples: fine for the small cells fracturing produces.

_3 private function(s) starting with `_` are not listed._
