# assets.gd

> Loads and caches the imported Kenney models and the meshes derived from them.

`res://scripts/client/assets.gd`

## Overview

Loads and caches the imported Kenney models and the meshes derived from them.

## Constants

- `const Split = preload("res://scripts/client/mesh_split.gd")`
- `const ROOT := "res://assets/kenney/"`
- `const BUILDINGS := ["city/building-small-a", "city/building-small-b", "city/building-small-c", "city/building-small-d", "city/building-garage"]`
- `const TREE_SCALE := 7.0 # The source trees are about 0.4 m tall on a 1 m tile.`
- `const PACKS := "res://assets/packs/"`
- `const BUILDING_FILES := ["village/EA03_Village_OutBuilding_Shed_01a", "village/EA03_Village_OutBuilding_Cubby_01d", "village/EA03_Village_OutBuilding_PentHou...`
- `const BUILDING_FOOTPRINT := 7.0 # Longest side of a house in meters (the server collides with a circle of 3.7 m).`
- `const WALL_LENGTH := 3.8`
- `const TREE_FILES := ["CommonTree_1", "CommonTree_2", "CommonTree_3", "CommonTree_4", "CommonTree_5", "Pine_1", "Pine_2", "Pine_3", "Pine_4", "Pine_5"]`
- `const ROCK_FILES := ["Rock_Medium_1", "Rock_Medium_2", "Rock_Medium_3"]`
- `const CHARACTER_NAMES := ["Elf_Male", "Elf_Female", "Orc_Male", "Orc_Female"]`
- `const PROP_FILES := ["EA03_Prop_Container_Barrel_01d", "EA03_Prop_Container_Crate_01a", "EA03_Prop_Town_Bench_01a", "EA03_Prop_Tabble_02a", "EA03_Prop_Contai...`
- `const TOWER_FILE := "EA03_Village_Tover_01a"`
- `const STATION_FILE := "EA03_Prop_Tabble_02a"`

## Functions

### `scene`

```gdscript
static func scene(path: String) -> PackedScene
```

### `instance`

```gdscript
static func instance(path: String) -> Node
```

### `mesh`

```gdscript
static func mesh(path: String) -> Mesh
```

The first mesh of a model (all of Kenney's props are a single mesh).

### `building_mesh`

```gdscript
static func building_mesh(variant: int) -> Mesh
```

### `tree_meshes`

```gdscript
static func tree_meshes() -> Array
```

Individual trees cut out of the "grass with trees" tiles: an array of Mesh, origin at the foot of the trunk.

### `sound`

```gdscript
static func sound(name: String) -> AudioStream
```

### `pack_exists`

```gdscript
static func pack_exists(relative: String) -> bool
```

### `has_nature`

```gdscript
static func has_nature() -> bool
```

### `has_village`

```gdscript
static func has_village() -> bool
```

### `has_characters`

```gdscript
static func has_characters() -> bool
```

### `has_survivors`

```gdscript
static func has_survivors() -> bool
```

Human survivors in clothes (Universal Base Characters + Modular Character Outfits, Quaternius, CC0), on the same
skeleton as the animation library. When installed they replace the bare fantasy bodies for players and settlers.

### `pack_mesh`

```gdscript
static func pack_mesh(relative: String) -> Mesh
```

The first mesh of a pack model (all of the props are one mesh with one or two surfaces).

### `nature_mesh`

```gdscript
static func nature_mesh(file: String) -> Mesh
```

### `village_mesh`

```gdscript
static func village_mesh(file: String) -> Mesh
```

### `fit_scale`

```gdscript
static func fit_scale(mesh: Mesh, target: float) -> float
```

Scale that makes a mesh's longest horizontal side `target` meters.

### `pack_building`

```gdscript
static func pack_building(variant: int) -> Dictionary
```

### `animation_library`

```gdscript
static func animation_library() -> AnimationLibrary
```

All animations of both libraries on one AnimationLibrary. Their tracks address "Armature/Skeleton3D:<bone>",
and every character of the Fantasy Races kit has exactly that skeleton, so they play on any of them.

