# model_catalog.gd

> The models of the downloaded packs, cut to size.

`res://scripts/client/model_catalog.gd`

## Overview

The models of the downloaded packs, cut to size. Most packs are collections (one file, dozens of objects, each far from the
origin and in its own units), so every model is baked once into its own mesh: the node's transform applied, scaled to a
target size in meters, and moved so that its bottom centre sits at the origin. The result can go straight into a MultiMesh.
Lists are filtered to what is actually installed: a missing pack just shortens a list, and an empty list means "use the
Kenney fallback". Which entry a house or prop takes is `variant % available.size()`, so the world data never has to know.

## Constants

- `const PACKS := "res://assets/packs/"`
- `const MeshLOD = preload("res://scripts/client/mesh_lod_preservation.gd")`
- `const MeshPBR = preload("res://scripts/client/mesh_pbr_preservation.gd")`
- `const StoneMicrodetail = preload("res://scripts/client/graphics_stone_microdetail.gd")`
- `const HOUSES := [`
- `const TOWN_CENTER_VARIANT := 7 # Index in HOUSES: the big building in the middle of a village.`
- `const TOWERS := [`
- `const BARRICADE_MODELS := [`
- `const WALLS := [`
- `const WALL_STONE := 1 # Indices of WALLS for forts and cities, and for farms and villages.`
- `const WALL_WOOD := 2`
- `const PROPS := [`
- `const RUINS := [`
- `const MONUMENTS := [`
- `const CRATES := [`
- `const PAINTED_TREES := ["Object_6", "Object_8", "Object_10", "Object_12", "Object_14", "Object_16", "Object_18", "Object_20", "Object_22", "Object_24"]`
- `const PAINTED_TREE_FILE := "loose/stylized_hand_painted_trees.glb"`
- `const STONES := ["Mid_1_MID_0", "Mid_2_MID_0", "Mid_3_MID_0", "Mid_5_MID_0", "Big_2_BiG_0", "Big_3_BiG_0", "BIG_1_BiG_0", "Small_1_SMall_0"]`
- `const STONE_FILE := "loose/stone_pack.glb"`
- `const CRYSTALS := [`
- `const BUILTIN_TREES := [`
- `const DECOR_EXTRA := [`
- `const SCANNED_ROCKS := ["boulder_01", "boulder_02", "boulder_04", "mossy_rock_1", "mossy_rock_2", "mossy_rock_3", "mossy_rock_4", "mossy_rock_5", "mossy_rock...`

## Functions

### `barricade_mesh`

```gdscript
static func barricade_mesh(tier: int) -> Mesh
```

The wall model of a tier (1..4), or null when its pack is missing.

### `full_path`

```gdscript
static func full_path(path: String) -> String
```

Paths are relative to the downloaded packs unless they start with res:// (the Poly Haven models in the repository).

### `exists`

```gdscript
static func exists(relative: String) -> bool
```

### `available`

```gdscript
static func available(list_name: String, list: Array) -> Array
```

The entries of a list whose files are installed, in list order.

### `pick`

```gdscript
static func pick(list_name: String, list: Array, variant: int) -> Dictionary
```

The entry for a variant number (variant % available), or {} when nothing of the list is installed.

### `entry_mesh`

```gdscript
static func entry_mesh(entry: Dictionary) -> Mesh
```

### `bake`

```gdscript
static func bake(path: String, node_name: String, kind: String, size: float, texture_path: String = "", yaw: float = 0.0) -> Mesh
```

One object of a model file, transformed, scaled and recentred. `node` empty takes the first mesh that is not a collision hull.

### `scanned_rock`

```gdscript
static func scanned_rock(variant: int) -> Mesh
```

### `has_scanned_rocks`

```gdscript
static func has_scanned_rocks() -> bool
```

### `painted_tree`

```gdscript
static func painted_tree(variant: int) -> Mesh
```

### `stone`

```gdscript
static func stone(variant: int) -> Mesh
```

### `monument`

```gdscript
static func monument(variant: int) -> Mesh
```

The model of a landmark piece, or null when none of its candidates is installed.

### `has_painted_trees`

```gdscript
static func has_painted_trees() -> bool
```

### `has_stones`

```gdscript
static func has_stones() -> bool
```

### `windmill`

```gdscript
static func windmill() -> Dictionary
```

The windmill: body and sails are separate files that share one origin; the sails get the body's scale and offset so they
fit, and are returned with the pivot they turn about.

_3 private function(s) starting with `_` are not listed._
