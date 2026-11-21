# gradient_batch.gd

> One native call for a color ramp's packed sample positions.

`res://scripts/client/gradient_batch.gd`

## Overview

One native call for a color ramp's packed sample positions. The scalar path
keeps the client compatible with stock Godot and standalone test runners.

## Functions

### `make_gradient`

```gdscript
static func make_gradient(first: Color, last: Color) -> Gradient
```

### `sample_many`

```gdscript
static func sample_many(gradient: Gradient, offsets: PackedFloat32Array, force_scalar: bool = false) -> PackedColorArray
```

