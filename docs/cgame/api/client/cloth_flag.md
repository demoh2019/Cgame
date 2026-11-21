# cloth_flag.gd

> Vertex-shader cloth for outpost banners (Unity Cloth component / Unreal Chaos Cloth, in a cheap analytic form): a subdivided plane pinned along the pole edge...

`res://scripts/client/cloth_flag.gd`

## Overview

Vertex-shader cloth for outpost banners (Unity Cloth component / Unreal Chaos Cloth, in a cheap analytic form):
a subdivided plane pinned along the pole edge whose free end ripples in the weather wind. The waving travels
down the flag, the free edge droops with gravity and lifts with wind strength; no CPU work per frame.
Wind comes from the same global the vegetation uses (aa_vegetation_wind: xy direction, z strength).

## Constants

- `const SEGMENTS := [0, 6, 12, 20] # Width subdivisions per quality tier; 0 keeps the rigid flag on Low.`
- `const SIZE := Vector2(2.4, 1.5)`
- `const SHADER_CODE := """`

## Functions

### `segments`

```gdscript
static func segments(level: int) -> int
```

### `build_mesh`

```gdscript
static func build_mesh(width_segments: int) -> ArrayMesh
```

A plane facing +Z with UV.x along the free direction, origin at the pole edge (x from 0 to width).

### `make_material`

```gdscript
static func make_material() -> ShaderMaterial
```

### `upgrade`

```gdscript
static func upgrade(flag: MeshInstance3D, level: int) -> ShaderMaterial
```

Replace a rigid flag mesh with the cloth one; returns the ShaderMaterial (null on Low, flag unchanged).

### `tint`

```gdscript
static func tint(material: Material, color: Color) -> void
```

