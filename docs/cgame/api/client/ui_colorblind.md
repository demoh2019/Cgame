# ui_colorblind.gd

> Full-screen colour-vision-deficiency filters (Unity post-processing colour-blind volume, Unreal "Color Blind Mode" accessibility setting).

`res://scripts/client/ui_colorblind.gd`

## Overview

Full-screen colour-vision-deficiency filters (Unity post-processing colour-blind volume, Unreal
"Color Blind Mode" accessibility setting). The matrices are Machado et al. 2009 at severity 1.0 for
protanopia, deuteranopia and tritanopia, applied to linear-ish screen colour after the HUD is drawn.

## Constants

- `const MATRICES := {`
- `const SHADER_CODE := """`

## Functions

### `rows`

```gdscript
static func rows(mode: int) -> Array
```

Matrix rows for a filter mode (0 = identity).

### `transform`

```gdscript
static func transform(color: Color, mode: int) -> Color
```

Applies the 3x3 matrix to a colour (CPU reference used by the tests and by anything that tints UI).

### `make_material`

```gdscript
static func make_material(mode: int) -> ShaderMaterial
```

### `configure`

```gdscript
static func configure(material: ShaderMaterial, mode: int) -> void
```

