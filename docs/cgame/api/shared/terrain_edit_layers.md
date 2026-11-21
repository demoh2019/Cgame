# terrain_edit_layers.gd

> Chunked, non-destructive terrain editing core.

`res://scripts/shared/terrain_edit_layers.gd`

## Overview

```text
Chunked, non-destructive terrain editing core.

Concepts ported from (clean-room reimplementation in GDScript, no code copied):
  - Terrain3D (TokisanGames/Terrain3D), MIT License, (c) Cory Petkovsek, Roope Palmroos,
    and contributors: region/chunk storage, brush falloff, splat (control map) painting.
  - Unreal Engine Landscape edit layers (concept only; no source used): ordered height
    layers with visibility, alpha and blend modes composited over a base heightfield.

Layout: a heightfield of `width` x `height` texels. A chunk covers `chunk_size` cells,
i.e. chunk (cx, cz) spans texels [cx*cs .. cx*cs+cs] inclusive, so neighbouring chunks
share a seam row/column. Exports add a 1-texel border for seamless normals.
Layers store a height delta + alpha; the base heights are never modified.
Layer property changes (visibility, opacity, blend, order) are not on the undo stack;
brush strokes and fills are.
```

## Constants

- `enum Blend { ADD, MAX, REPLACE }`
- `enum Brush { RAISE, LOWER, SMOOTH, FLATTEN, NOISE, ERODE }`
- `enum Falloff { LINEAR, SMOOTH, SPHERE, CONSTANT }`
- `enum UndoKind { HEIGHT, SPLAT }`

## Classes

- `class EditLayer extends RefCounted:`
- `class UndoEntry extends RefCounted:`

## Documented variables

- `var max_undo_bytes: int = 8 * 1024 * 1024` - Upper bound on undo+redo history memory. Oldest entries are dropped first.

## Functions

### `setup`

```gdscript
func setup(p_width: int, p_height: int, p_chunk_size: int, base_heights: PackedFloat32Array) -> void
```

### `chunk_count`

```gdscript
func chunk_count() -> int
```

### `add_layer`

```gdscript
func add_layer(p_name: String, blend: int = Blend.ADD, opacity: float = 1.0) -> int
```

### `remove_layer`

```gdscript
func remove_layer(id: int) -> bool
```

### `move_layer`

```gdscript
func move_layer(id: int, to_index: int) -> bool
```

Moves a layer to `to_index` in the stack (0 = bottom, composited first).

### `set_layer_visible`

```gdscript
func set_layer_visible(id: int, p_visible: bool) -> void
```

### `set_layer_opacity`

```gdscript
func set_layer_opacity(id: int, p_opacity: float) -> void
```

### `set_layer_blend`

```gdscript
func set_layer_blend(id: int, blend: int) -> void
```

### `layer_count`

```gdscript
func layer_count() -> int
```

### `layer_ids`

```gdscript
func layer_ids() -> PackedInt32Array
```

Layer ids from bottom to top.

### `composite_height`

```gdscript
func composite_height(x: int, y: int) -> float
```

### `composite_region`

```gdscript
func composite_region(rect: Rect2i) -> PackedFloat32Array
```

Composite heights for `rect` (clipped to the map), row-major, rect.size.x per row.

### `fill_layer_rect`

```gdscript
func fill_layer_rect(id: int, rect: Rect2i, delta: float, alpha: float = 1.0) -> void
```

Writes `delta`/`alpha` into the whole rect of a layer (undoable).

### `layer_delta_at`

```gdscript
func layer_delta_at(id: int, x: int, y: int) -> float
```

### `apply_brush`

```gdscript
func apply_brush(layer_id: int, brush: int, center: Vector2, radius: float, strength: float, falloff: int = Falloff.SMOOTH, target_height: float = 0.0, seed_value: int = 0, curve: Curve = null) -> Rect2i
```

Applies a height brush to one edit layer. Returns the changed rect (empty if none).
`target_height` is used by FLATTEN; `seed_value` by NOISE.

### `setup_splat`

```gdscript
func setup_splat(count: int) -> void
```

Creates `count` material layers per texel; layer 0 starts at weight 1.

### `splat_count`

```gdscript
func splat_count() -> int
```

### `splat_weights`

```gdscript
func splat_weights(x: int, y: int) -> PackedFloat32Array
```

### `paint_splat`

```gdscript
func paint_splat(material: int, center: Vector2, radius: float, strength: float, falloff: int = Falloff.SMOOTH, curve: Curve = null) -> Rect2i
```

Paints material `material` with the brush; other weights shrink so the sum stays 1.

### `undo_bytes`

```gdscript
func undo_bytes() -> int
```

### `undo_depth`

```gdscript
func undo_depth() -> int
```

### `can_undo`

```gdscript
func can_undo() -> bool
```

### `can_redo`

```gdscript
func can_redo() -> bool
```

### `undo`

```gdscript
func undo() -> bool
```

### `redo`

```gdscript
func redo() -> bool
```

### `take_dirty_chunks`

```gdscript
func take_dirty_chunks() -> Array[Vector2i]
```

Chunks touched since the previous call (sorted by z then x); clears the set.

### `collision_jobs`

```gdscript
func collision_jobs(max_per_frame: int) -> Array[Vector2i]
```

Pops up to `max_per_frame` distinct chunks needing a collision rebuild (oldest first).

### `pending_collision_count`

```gdscript
func pending_collision_count() -> int
```

### `export_chunk_heights`

```gdscript
func export_chunk_heights(chunk: Vector2i) -> PackedFloat32Array
```

Heights for a chunk with a 1-texel border: (chunk_size + 3)^2 values, row-major.
Index (i, j) is texel (cx*cs - 1 + i, cz*cs - 1 + j); out-of-map texels clamp to the edge.

### `build_chunk_mesh`

```gdscript
func build_chunk_mesh(chunk: Vector2i, cell_size: float) -> ArrayMesh
```

Builds the chunk's mesh in chunk-local space (origin at the chunk's min corner).
Normals use the exported border so lighting is continuous across seams.
ARRAY_COLOR carries the first four splat weights (when splat is set up).

_16 private function(s) starting with `_` are not listed._
