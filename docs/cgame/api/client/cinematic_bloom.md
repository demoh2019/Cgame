# cinematic_bloom.gd

> (no header comment)

`res://scripts/client/cinematic_bloom.gd`

## Constants

- `const CinematicColorGrade = preload("res://scripts/client/cinematic_color_grade.gd")` - HDR camera-lens bloom tuned for sky, weather and golden-hour lighting. High/Ultra reuse the existing Godot native glow chain; no extra pass, blur material, extra emissive objects or separate screen texture.

## Functions

### `look`

```gdscript
static func look(level: int, method: String, daylight: float, sun_height: float, storm: float) -> Dictionary
```

Pure scene-referred optics policy. Quantizing to hundredths both bounds
the look and avoids repeated C++ environment updates as weather eases.

### `apply`

```gdscript
static func apply(environment: Environment, level: int, method: String, daylight: float, sun_height: float, storm: float) -> void
```

