# foliage.gd

> Wind for the nature kit: a copy of a mesh whose materials sway with the wind, strongest at the tips.

`res://scripts/client/foliage.gd`

## Overview

Wind for the nature kit: a copy of a mesh whose materials sway with the wind, strongest at the tips.
The textures and alpha cut-outs of the original materials are kept.

## Constants

- `const SHADER_CODE := """`
- `const MeshLOD = preload("res://scripts/client/mesh_lod_preservation.gd")`

## Functions

### `supports_alpha_coverage`

```gdscript
static func supports_alpha_coverage(method: String, msaa: int) -> bool
```

Alpha-to-coverage is supported only by the Vulkan renderers with actual MSAA.
FSR2 provides its own AA and disables MSAA, so that path uses the original shader.

### `configure_antialiasing`

```gdscript
static func configure_antialiasing(enabled: bool) -> void
```

Switching quality changes the shader of already cached instances in place:
no mesh regeneration, no texture duplication and no world-chunk rebuild.

### `alpha_mipmaps_enabled`

```gdscript
static func alpha_mipmaps_enabled(quality: int, method: String) -> bool
```

Alpha coverage mipmaps keep small leaves and thin branches visible
after minification. FSR2 benefits too: this is independent of MSAA.

### `configure_alpha_mipmaps`

```gdscript
static func configure_alpha_mipmaps(quality: int, method: String) -> void
```

Quality changes only update cached materials, never mesh geometries.

### `fade_role_for`

```gdscript
static func fade_role_for(key: String) -> int
```

The exact scene-category fade ranges are shared through global uniforms.
Never apply the tree/bush range to monuments or decor with authored ranges.

### `swayed`

```gdscript
static func swayed(source: Mesh, key: String, sway: float, tinted: bool = false) -> Mesh
```

A swaying copy of `source` (cached by key). `sway` is the tip displacement in meters. `tinted`: multiply by the
MultiMesh instance colour.

_4 private function(s) starting with `_` are not listed._
