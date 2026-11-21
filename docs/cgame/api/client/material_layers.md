# material_layers.gd

> Layered material authoring: turns a layer-stack description into Godot 4 spatial shader source.

`res://scripts/client/material_layers.gd`

## Overview

```text
Layered material authoring: turns a layer-stack description into Godot 4 spatial shader source.

Stack format:
  {"normal_blend": "rnm"|"udn", "functions": ["fn_name" | {"name": String, "code": String}],
   "layers": [{"name", "albedo": Color|texture path, "tint": Color, "normal": texture path,
               "roughness", "metallic", "normal_strength", "uv_scale", "height", "height_var",
               "triplanar": bool, "triplanar_sharpness",
               "blend": {"mode": "height"|"slope"|"noise"|"mask_channel"|"vertex_color",
                         "amount", "contrast", "min", "max", "invert", "scale", "threshold",
                         "softness", "channel": "r|g|b|a", "texture": path}}]}
Layer 0 is the base (its blend is ignored); each later layer is blended over the accumulated result,
with a height-contest (Unreal "height lerp"/Substance height blend) applied to the blend weight.

Shader Permutation Reduction: only the stack STRUCTURE (layer count/names, texture-vs-color slots,
blend modes/channels, triplanar flags, functions) changes the generated code. All numeric values are
uniforms, so parameter-only differences reuse one cached Shader; build_material() / instance() just
set shader parameters (a Material Instance shares the parent Shader).

Sources / credits (techniques re-implemented from the published math, no third-party code pasted
except as noted; no GPL/LGPL and no Apache-2.0 code used):
 - Hash without Sine (hash13 constants): Dave Hoskins, https://www.shadertoy.com/view/4djSRW, MIT.
 - Reoriented Normal Mapping & UDN blend: Colin Barre-Brisebois and Stephen Hill, "Blending in Detail",
   https://blog.selfshadow.com/publications/blending-in-detail/ (formulas; reimplemented).
 - Triplanar mapping: Ben Golus, "Normal Mapping for a Triplanar Shader" (technique; reimplemented).
 - Height-lerp blend: Bruno Opsenica "Advanced Terrain Texture Splatting" (technique; reimplemented).
 - Layer-stack/instance model: Unreal Engine Material Layers / Material Functions concept (design only).
```

## Constants

- `const MODE_HEIGHT := "height"`
- `const MODE_SLOPE := "slope"`
- `const MODE_NOISE := "noise"`
- `const MODE_MASK := "mask_channel"`
- `const MODE_VERTEX_COLOR := "vertex_color"`
- `const FN_LIBRARY := {` - Material function library: name -> {"deps": Array, "code": String}. Injected once per shader.

## Functions

### `function_names`

```gdscript
static func function_names() -> Array
```

### `get_function`

```gdscript
static func get_function(fn_name: String) -> String
```

### `layer_prefix`

```gdscript
static func layer_prefix(stack: Dictionary, index: int) -> String
```

### `generate_shader_code`

```gdscript
static func generate_shader_code(stack: Dictionary) -> String
```

### `structure_key`

```gdscript
static func structure_key(stack: Dictionary) -> String
```

Structure-only signature: equal for stacks that differ only in numeric/colour/texture VALUES.

### `get_shader`

```gdscript
static func get_shader(stack: Dictionary) -> Shader
```

Returns the cached Shader for this stack's structure, generating it on first use.

### `clear_cache`

```gdscript
static func clear_cache() -> void
```

### `cache_size`

```gdscript
static func cache_size() -> int
```

### `collect_params`

```gdscript
static func collect_params(stack: Dictionary) -> Dictionary
```

All uniform values of a stack: uniform name -> value (Color/float/Texture2D).

### `build_material`

```gdscript
static func build_material(stack: Dictionary) -> ShaderMaterial
```

### `instance`

```gdscript
static func instance(base: ShaderMaterial, overrides: Dictionary) -> ShaderMaterial
```

Material Instance: shares base's Shader, copies its parameters, applies overrides.
Override keys are full uniform names or "layer_name/param" (e.g. "mud/roughness").

_9 private function(s) starting with `_` are not listed._
