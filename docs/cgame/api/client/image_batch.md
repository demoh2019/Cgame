# image_batch.gd

> CPU image subrectangle updates shared by world atlas and procedural sky LUTs.

`res://scripts/client/image_batch.gd`

## Overview

CPU image subrectangle updates shared by world atlas and procedural sky LUTs.
Cgame's native packed write avoids a script/native crossing for every pixel.
Stock Godot uses the original pixel-by-pixel equivalent.

## Functions

### `set_rect`

```gdscript
static func set_rect(image: Image, rect: Rect2i, colors: PackedColorArray, force_scalar: bool = false) -> bool
```

### `set_row`

```gdscript
static func set_row(image: Image, y: int, colors: PackedColorArray, force_scalar: bool = false) -> bool
```

