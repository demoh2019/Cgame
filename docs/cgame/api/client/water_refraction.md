# water_refraction.gd

> (no header comment)

`res://scripts/client/water_refraction.gd`

## Constants

- `const BASE_SHADER = preload("res://assets/shaders/water.gdshader")` - Two cacheable variants of the same ocean shader. On low presets and non-Forward+ backends the screen sampler is preprocessed away.

## Functions

### `enabled`

```gdscript
static func enabled(level: int, method: String) -> bool
```

### `shader_for`

```gdscript
static func shader_for(level: int, method: String) -> Shader
```

### `apply`

```gdscript
static func apply(material: ShaderMaterial, profile: Dictionary, level: int, method: String) -> void
```

