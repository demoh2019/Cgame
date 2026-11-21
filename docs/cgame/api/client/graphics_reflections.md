# graphics_reflections.gd

> (no header comment)

`res://scripts/client/graphics_reflections.gd`

## Documented variables

- `static var _last_roughness_quality: int = -1` - Hybrid reflection budget: sky radiance remains the off-screen fallback, while Forward+ adds SSR contacts to opaque PBR objects at High/Ultra only. Transparent water has its own reflection model and does not enter opaque SSR. Native SSR roughness-mip filtering changes only on quality/profile switches.

## Functions

### `settings`

```gdscript
static func settings(level: int, rendering_method: String) -> Dictionary
```

### `apply`

```gdscript
static func apply(environment: Environment, level: int, rendering_method: String) -> void
```

