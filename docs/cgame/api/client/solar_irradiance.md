# solar_irradiance.gd

> (no header comment)

`res://scripts/client/solar_irradiance.gd`

## Constants

- `const SAMPLE_INTERVAL := 0.20` - Cheap, scene-wide spectral solar tint. The native sky model supplies a single transmittance RGB sample at 5 Hz; existing sun lighting, terrain, foliage, water and atmosphere all receive the same directional light.

## Functions

### `valid`

```gdscript
static func valid(sample: Color) -> bool
```

### `tint`

```gdscript
static func tint(artist: Color, optical: Color, strength: float) -> Color
```

Mix normalized optical transmittance into the current art-directed tint.
The midday optical sample is white, so existing exposure remains stable.

### `supported`

```gdscript
static func supported(strength: float, rendering_method: String) -> bool
```

