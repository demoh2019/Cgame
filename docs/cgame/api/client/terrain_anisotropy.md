# terrain_anisotropy.gd

> Texture-group-style sampler budgets for the existing 13-layer terrain PBR shader.

`res://scripts/client/terrain_anisotropy.gd`

## Overview

Texture-group-style sampler budgets for the existing 13-layer terrain PBR shader.
Like desktop engine scalability settings, only the expensive terrain samplers
use anisotropy at High/Ultra. Compatibility and Forward+ use the same
shader language and exactly the same texture arrays / per-chunk uniforms.

## Constants

- `const SOURCE_PATH := "res://assets/shaders/ground.gdshader"`
- `const ALBEDO_LINEAR := "uniform sampler2DArray albedo_layers : source_color, filter_linear_mipmap, repeat_enable;"`
- `const NORMAL_LINEAR := "uniform sampler2DArray normal_layers : hint_normal, filter_linear_mipmap, repeat_enable;"`
- `const ALBEDO_ANISO := "uniform sampler2DArray albedo_layers : source_color, filter_linear_mipmap_anisotropic, repeat_enable;"`
- `const NORMAL_ANISO := "uniform sampler2DArray normal_layers : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;"`
- `const WET_COAT_DEFINE := "\n#define AA_TERRAIN_WET_CLEARCOAT"`
- `const PARAMETERS := [`

## Functions

### `tier_for_quality`

```gdscript
static func tier_for_quality(quality: int) -> int
```

0: standard trilinear, 1: anisotropic ground color, 2: color + normals.
Normal filtering costs extra bandwidth, so it is exclusive to Ultra.

### `code_for_tier`

```gdscript
static func code_for_tier(source: String, tier: int) -> String
```

Pure shader-source change: preserve all texture names and uniform layout.

### `shader_for_quality`

```gdscript
static func shader_for_quality(quality: int) -> Shader
```

### `apply`

```gdscript
static func apply(material: ShaderMaterial, quality: int) -> void
```

Called at preset changes only, never per frame or per terrain vertex.

