# mesh_split.gd

> Splits a mesh into its connected pieces.

`res://scripts/client/mesh_split.gd`

## Overview

Splits a mesh into its connected pieces. Kenney's "grass with trees" tiles hold several trees as
separate islands of triangles sitting on a ground block, so splitting by connectivity gives the
individual trees.

## Constants

- `const QUANTIZE := 1000.0`

## Functions

### `split`

```gdscript
static func split(source: Mesh, min_y: float = 0.0, merge_xz: float = 0.0) -> Array
```

Returns an array of {"mesh": ArrayMesh, "center": Vector3 (bottom center), "size": Vector3}, one per
piece, for the triangles whose lowest vertex is at least `min_y` above the mesh origin.

_1 private function(s) starting with `_` are not listed._
