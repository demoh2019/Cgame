# loot_beam.gd

> Loot beams by value (Diablo IV / Borderlands): a light column above notable loot so it reads from across the map.

`res://scripts/client/loot_beam.gd`

## Overview

Loot beams by value (Diablo IV / Borderlands): a light column above notable
loot so it reads from across the map. Display-only, from snapshot flags.

## Constants

- `const SHADER := preload("res://assets/shaders/loot_beam.gdshader")`
- `const NODE_NAME := &"LootBeam"`

## Functions

### `color_for`

```gdscript
static func color_for(bag: Dictionary) -> Color
```

Beam colour for a bag; alpha 0 means no beam (ordinary public loot).

### `make`

```gdscript
static func make() -> MeshInstance3D
```

### `update`

```gdscript
static func update(root: Node, bag: Dictionary) -> void
```

Called on every snapshot update; only touches the material when the colour changes.

