# probe_volume.gd

> Adaptive irradiance probe volume with L2 SH probes, temporal radiance-cache style updates and LRU-budgeted cell streaming.

`res://scripts/shared/probe_volume.gd`

## Overview

```text
Adaptive irradiance probe volume with L2 SH probes, temporal radiance-cache
style updates and LRU-budgeted cell streaming.

Concepts (re-implemented from published descriptions; no third-party code):
 - Majercik et al., "Dynamic Diffuse Global Illumination with Ray-Traced
   Irradiance Fields" (JCGT 2019): probe rays, hysteresis blending, backface
   weighting (dot+1)/2 squared + 0.2, invalid probes inside geometry.
 - Unity Adaptive Probe Volumes: bricks subdivided where density is high,
   streaming in cells.
 - Ramamoorthi & Hanrahan 2001 / Sloan 2008 for SH irradiance (see sh_lighting.gd).
Geometry is abstracted behind a trace Callable(origin, dir) -> Dictionary
{hit: bool, color: Color (outgoing radiance), distance: float, backface: bool (optional)}.
```

## Constants

- `const SHLighting = preload("res://scripts/shared/sh_lighting.gd")`
- `const MAX_LEVEL: int = 2`
- `const CELL_SPAN: int = 2` - Streaming cell edge, in base bricks.
- `const RECORD_BYTES: int = 4 + 1 + SHLighting.COEFFS * 3 * 4` - Serialized record: s32 index + u8 valid + 27 float32.

## Documented variables

- `var memory_budget_bytes: int = 0` - 0 means unlimited.

## Functions

### `clear`

```gdscript
func clear() -> void
```

### `probe_count`

```gdscript
func probe_count() -> int
```

### `probe_position`

```gdscript
func probe_position(i: int) -> Vector3
```

### `probe_sh`

```gdscript
func probe_sh(i: int) -> PackedColorArray
```

### `is_probe_valid`

```gdscript
func is_probe_valid(i: int) -> bool
```

### `find_probe`

```gdscript
func find_probe(pos: Vector3) -> int
```

### `sky`

```gdscript
func sky(dir: Vector3) -> Color
```

### `cell_of_position`

```gdscript
func cell_of_position(pos: Vector3) -> Vector3i
```

### `build`

```gdscript
func build(p_bounds: AABB, p_base_spacing: float, density_at: Callable) -> int
```

Builds bricks of base_spacing; density_at(center: Vector3) -> float in 0..1
picks the subdivision level (0..MAX_LEVEL). Returns the probe count.

### `bake`

```gdscript
func bake(trace: Callable, rays_per_probe: int, rng_seed: int) -> void
```

### `temporal_update`

```gdscript
func temporal_update(fraction: float, trace: Callable, rng_seed: int) -> int
```

Updates a rotating subset (fraction of all probes) and blends with the old
value using `hysteresis`. Returns the number of probes updated.

### `sample`

```gdscript
func sample(pos: Vector3, normal: Vector3) -> Color
```

Irradiance / pi at pos for surface normal, interpolated from the 8 corner
probes of the containing leaf (trilinear x validity x backface weight).

### `touch_cell`

```gdscript
func touch_cell(cell: Vector3i) -> void
```

### `is_cell_resident`

```gdscript
func is_cell_resident(cell: Vector3i) -> bool
```

### `cell_probe_ids`

```gdscript
func cell_probe_ids(cell: Vector3i) -> PackedInt32Array
```

### `resident_bytes`

```gdscript
func resident_bytes() -> int
```

### `cells_needed`

```gdscript
func cells_needed(view_pos: Vector3, radius: float) -> Array
```

Cells whose volume intersects the sphere (view_pos, radius), nearest first.

### `serialize_cell`

```gdscript
func serialize_cell(cell: Vector3i) -> PackedByteArray
```

### `load_cell`

```gdscript
func load_cell(cell: Vector3i, bytes: PackedByteArray) -> bool
```

Restores a serialized cell, marks it resident and enforces the budget
(never evicting the cell just loaded). Returns false on malformed data.

### `unload_cell`

```gdscript
func unload_cell(cell: Vector3i) -> PackedByteArray
```

Serializes, stores and frees a cell's probe data. Returns the bytes.

### `request_cell`

```gdscript
func request_cell(cell: Vector3i) -> bool
```

Loads an evicted cell from the internal store.

### `enforce_budget`

```gdscript
func enforce_budget(protect: Vector3i = Vector3i(-99999, -99999, -99999)) -> int
```

Evicts least-recently-used cells until resident_bytes() <= memory_budget_bytes.
The `protect` cell and the most recently used cell are kept. Returns evictions.

_7 private function(s) starting with `_` are not listed._
