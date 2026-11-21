# character_shading.gd

> Specialised character shading on top of standard PBR, like UE5 Substrate hair/cloth/eye models and HDRP Hair/Fabric/Eye shaders: - hair: anisotropic Kajiya-s...

`res://scripts/client/character_shading.gd`

## Overview

Specialised character shading on top of standard PBR, like UE5 Substrate
hair/cloth/eye models and HDRP Hair/Fabric/Eye shaders:
- hair: anisotropic Kajiya-style highlight along strands plus backlit rim;
- cloth: fuzzy sheen at grazing angles (rim), never glossy;
- eyes: wet clearcoat cornea over the iris.
Skin is left to native subsurface scattering (graphics_skin_scattering.gd).

## Functions

### `configure`

```gdscript
static func configure(level: int) -> void
```

### `kind_of`

```gdscript
static func kind_of(material_name: String) -> String
```

### `enhance`

```gdscript
static func enhance(material: BaseMaterial3D, kind: String, level: int = -1) -> bool
```

Mutates a material the caller already owns (a duplicate). Returns true if changed.

### `enhance_model`

```gdscript
static func enhance_model(root: Node, level: int = -1) -> int
```

Gives every non-skin surface of an assembled character its own enhanced material.

