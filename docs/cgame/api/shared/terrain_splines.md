# terrain_splines.gd

> Spline-based world authoring helpers for roads, rivers, bridges and landscape deformation.

`res://scripts/shared/terrain_splines.gd`

## Overview

Spline-based world authoring helpers for roads, rivers, bridges and landscape
deformation. Inspired by Unreal Engine's Landscape Splines (deform terrain along
a spline) and the road/river tooling of World Machine and Gaea.
Heights are indexed y * width + x; world position of a cell is (x, y) * cell_size
on the XZ plane (Vector3.x, Vector3.z), spline height is Vector3.y.

## Functions

### `catmull_rom`

```gdscript
static func catmull_rom(points: PackedVector3Array, samples_per_segment: int) -> PackedVector3Array
```

Uniform Catmull-Rom through all control points (end points are duplicated).
Result includes every control point exactly.

### `distance_to_polyline`

```gdscript
static func distance_to_polyline(p: Vector2, polyline: PackedVector2Array) -> float
```

Distance from `p` to the closest point of a polyline.

### `deform`

```gdscript
static func deform(heights: PackedFloat32Array, width: int, height: int, cell_size: float, spline: PackedVector3Array, half_width: float, falloff: float, mode: String) -> PackedFloat32Array
```

Deforms the heightmap around a spline. Returns a new array.
mode: "flatten" blends terrain toward the spline height (road),
"carve" lowers a channel 1.0 below the spline at its centre with smooth banks (river),
"raise" only ever lifts terrain up to the spline height (embankment).
Full effect within `half_width`, smooth falloff over the next `falloff` units.

### `bridge_spans`

```gdscript
static func bridge_spans(heights: PackedFloat32Array, width: int, height: int, cell_size: float, spline: PackedVector3Array, clearance: float = 2.0) -> Array
```

Index ranges [start, end] (inclusive) of spline samples that float more than
`clearance` above the terrain, i.e. where a bridge is required.

_2 private function(s) starting with `_` are not listed._
