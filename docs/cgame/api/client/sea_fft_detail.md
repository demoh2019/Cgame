# sea_fft_detail.gd

> Tessendorf FFT chop on top of the sea's Gerstner swell (Sea of Thieves / Atlas / UE Water style).

`res://scripts/client/sea_fft_detail.gd`

## Overview

Tessendorf FFT chop on top of the sea's Gerstner swell (Sea of Thieves /
Atlas / UE Water style). The CPU spectrum is evaluated 10 times a second
into two small height textures; the water shader cross-fades them every
frame, so motion stays smooth at ~1 ms of script time per update.
High/Ultra only; lower presets keep the pure Gerstner surface.

## Constants

- `const FftOcean = preload("res://scripts/shared/fft_ocean.gd")`
- `const QUALITY_SCRIPT := "res://scripts/client/graphics_quality.gd"`
- `const GRID := 32`
- `const PATCH := 48.0 # Metres per tile; the shader repeats it.`
- `const STEP := 0.1`
- `const STRENGTH := [0.0, 0.0, 0.18, 0.26]`

## Functions

### `strength_for`

```gdscript
static func strength_for(level: int) -> float
```

### `setup`

```gdscript
func setup(material: ShaderMaterial, level: int, seed: int = 1337) -> void
```

### `configure`

```gdscript
func configure(level: int) -> void
```

_2 private function(s) starting with `_` are not listed._
