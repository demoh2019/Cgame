# material_presets.gd

> Layer stacks for the game's surfaces, consumed by material_layers.gd (build_material / instance).

`res://scripts/client/material_presets.gd`

## Overview

Layer stacks for the game's surfaces, consumed by material_layers.gd (build_material / instance).
Colour-only layers with procedural normals so they work without imported textures; swap an
"albedo" for a texture path (and add "normal") to upgrade a preset without touching the shader logic.

## Constants

- `const MaterialLayers = preload("res://scripts/client/material_layers.gd")`

## Functions

### `wet_mud_road`

```gdscript
static func wet_mud_road() -> Dictionary
```

### `mossy_ruin_stone`

```gdscript
static func mossy_ruin_stone() -> Dictionary
```

### `rusty_metal`

```gdscript
static func rusty_metal() -> Dictionary
```

### `snowy_cliff`

```gdscript
static func snowy_cliff() -> Dictionary
```

### `blood_soaked_ground`

```gdscript
static func blood_soaked_ground() -> Dictionary
```

### `all`

```gdscript
static func all() -> Dictionary
```

