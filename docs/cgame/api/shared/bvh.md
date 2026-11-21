# bvh.gd

> CPU bounding volume hierarchy over a triangle soup (binned SAH build, flat node arrays, Moller-Trumbore ray/triangle test).

`res://scripts/shared/bvh.gd`

## Overview

```text
CPU bounding volume hierarchy over a triangle soup (binned SAH build, flat node arrays,
Moller-Trumbore ray/triangle test). Used by the path tracer for light baking.

Ported from concepts and public write-ups; no third-party source text was copied:
 - Jacco Bikker, "How to build a BVH" series (binned SAH build, flat node layout, stackless-free
   stack traversal), https://jacco.ompf2.com/2022/04/13/how-to-build-a-bvh-part-1-basics/
   (article code is public domain / ZLIB-style permissive; algorithm re-implemented here).
 - Tomas Moller and Ben Trumbore, "Fast, Minimum Storage Ray/Triangle Intersection", 1997
   (published algorithm, J. Graphics Tools 2(1)).
 - Peter Shirley, "Ray Tracing in One Weekend" series (CC0), slab AABB test:
   https://raytracing.github.io/
 - Pharr/Jakob/Humphreys, "Physically Based Rendering" (BSD-2 code, pbrt-v3/v4), SAH bucket
   cost model: https://github.com/mmp/pbrt-v4
No Apache-2.0, GPL or LGPL code is included.
```

## Constants

- `const BINS := 16`
- `const MAX_LEAF := 2` - SAH may stop at or below this many triangles
- `const FORCE_SPLIT := 8` - leaves are never larger than this
- `const T_MIN := 0.00001`
- `const MISS := 1.0e30`

## Documented variables

- `var node_min := PackedVector3Array()` - Node i: bounds node_min/node_max. Leaf when node_cnt[i] > 0 (node_first[i] is the first slot in the leaf-ordered triangle arrays). Interior: node_first[i] is the left child, right = left + 1.
- `var tri_v0 := PackedVector3Array()` - Leaf-ordered triangle data (v0, v1 - v0, v2 - v0) and map back to the input triangle index.

## Functions

### `build`

```gdscript
func build(tris: PackedVector3Array) -> void
```

Builds the hierarchy; `tris` holds three vertices per triangle.

### `intersect`

```gdscript
func intersect(origin: Vector3, dir: Vector3, t_max: float = 1.0e20) -> Dictionary
```

Closest hit along origin + t * dir for t in (0, t_max]. `normal` is geometric and faces the ray.

### `occluded`

```gdscript
func occluded(origin: Vector3, dir: Vector3, t_max: float = 1.0e20) -> bool
```

Any-hit shadow query: true when something blocks origin + t * dir for t in (0, t_max).

### `get_stats`

```gdscript
func get_stats() -> Dictionary
```

Build statistics. sah_cost is the expected traversal cost relative to the root area.

_8 private function(s) starting with `_` are not listed._
