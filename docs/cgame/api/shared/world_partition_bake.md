# world_partition_bake.gd

> World Partition style scene baking: hierarchical grid cells, always-loaded actors, data layers, HLOD clusters, One-File-Per-Actor storage, incremental diffs ...

`res://scripts/shared/world_partition_bake.gd`

## Overview

```text
World Partition style scene baking: hierarchical grid cells, always-loaded
actors, data layers, HLOD clusters, One-File-Per-Actor storage, incremental
diffs and predictive streaming.

Concepts follow Unreal Engine 5 World Partition (runtime grid with grid
levels, Data Layers, One File Per Actor, HLOD). Only the publicly documented
ideas are used; no Epic source code is copied.
  https://dev.epicgames.com/documentation/en-us/unreal-engine/world-partition-in-unreal-engine
The implementation here is original code written for this project.
Navmesh tile stitching lives in navmesh_stitching.gd (Recast/Detour, zlib).
```

## Constants

- `const MAX_LEVEL := 8`
- `const DEFAULT_LAYER_KEY := "default"`

## Documented variables

- `var lookahead_seconds: float = 1.5` - Seconds of travel simulated ahead of the streaming source.
- `var lookahead_samples: int = 3` - Number of sample points along the look-ahead segment.

## Functions

### `stable_guid`

```gdscript
func stable_guid(seed_string: String) -> String
```

Deterministic GUID (UUID-shaped) from a seed string. Same seed, same GUID.

### `bake`

```gdscript
func bake(actors: Array, cell_size: float, loading_range_by_layer: Dictionary) -> Dictionary
```

### `hlod_clusters`

```gdscript
func hlod_clusters(cells: Dictionary, cluster_cells: int) -> Array
```

Groups baked cells into HLOD clusters of cluster_cells x cluster_cells cells
(in each cell's own grid level), keeping layer groups separate.

### `split_one_file_per_actor`

```gdscript
func split_one_file_per_actor(actors: Array, dir_path: String) -> int
```

Writes one <guid>.json per actor (tmp file + rename). Returns files written.

### `load_actors`

```gdscript
func load_actors(dir_path: String) -> Array
```

### `diff_bakes`

```gdscript
func diff_bakes(old_bake: Dictionary, new_bake: Dictionary) -> Dictionary
```

### `cells_to_load`

```gdscript
func cells_to_load(source_pos: Vector3, velocity: Vector3, layers_enabled: PackedStringArray) -> Array
```

Cells to stream in for a source, also sampling points along its velocity
(predictive look-ahead). Cells of disabled data layers are skipped.
Sorted nearest-first, using the most recent bake().

_7 private function(s) starting with `_` are not listed._
