# cloud_shadow_lut.gd

> (no header comment)

`res://scripts/client/cloud_shadow_lut.gd`

## Constants

- `const ImageBatch = preload("res://scripts/client/image_batch.gd")` - One small, seamless cloud-opacity lookup for terrain, grass and foliage. This replaces repeated multi-octave hash/sine noise at every rendered pixel. A deterministic CPU build runs once; the texture stays cached across chunks.
- `const ScalarGridSampler = preload("res://scripts/client/scalar_grid_sampler.gd")`
- `const SIZE := 128`
- `const TILE_METERS := 1024.0`
- `const MAX_CLOUD_SPEED := 7.5 # m/s at full regional wind; clouds move over the existing large texture.`
- `const PERIODS := [8, 18, 36]`
- `const WEIGHTS := [0.56, 0.30, 0.14]`
- `const SEED := 220716`

## Functions

### `build_image`

```gdscript
static func build_image(force_scalar: bool = false) -> Image
```

### `texture`

```gdscript
static func texture() -> ImageTexture
```

### `world_uv`

```gdscript
static func world_uv(position: Vector2, elapsed: float) -> Vector2
```

Normalized and scrolling UVs remain continuous across world/chunk borders.

### `advance_offset`

```gdscript
static func advance_offset(previous: Vector2, wind: Vector3, delta: float) -> Vector2
```

Integrate one wind-driven cloud position in metres. A wrapped offset avoids
precision loss over long sessions; one full 1024 m wrap is texture-periodic.
The actual cloud LUT is still built once, never resampled or regenerated.
The vector is already-smoothed vegetation wind: xy direction, z strength.

### `wind_uv`

```gdscript
static func wind_uv(position: Vector2, offset: Vector2) -> Vector2
```

Pure shader-equivalent UV helper for regression tests and debug views.

### `shadow_strength`

```gdscript
static func shadow_strength(daylight: float, storm: float, enabled: bool = true) -> float
```

_1 private function(s) starting with `_` are not listed._
