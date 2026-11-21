# fft_ocean.gd

> Tessendorf FFT ocean heightfield ("Simulating Ocean Water", 2001), the technique behind the Sea of Thieves / Atlas oceans and Unreal's Water plugin far-field...

`res://scripts/shared/fft_ocean.gd`

## Overview

Tessendorf FFT ocean heightfield ("Simulating Ocean Water", 2001), the
technique behind the Sea of Thieves / Atlas oceans and Unreal's Water plugin
far-field waves. A Phillips spectrum h0(k) is built once from a seed; each
frame h(k,t) = h0(k) e^{iwt} + conj(h0(-k)) e^{-iwt} (w = sqrt(g|k|), deep
water dispersion) is transformed by an inverse 2D FFT into a real, tileable
height grid that can be sampled on the CPU (buoyancy) or uploaded as a
shader texture (vertex displacement).

## Constants

- `const GRAVITY: float = 9.81`

## Documented variables

- `var last_max_imag: float = 0.0` - Largest |imag| seen by the last evaluate() (should be ~0 for a real field).

## Functions

### `setup`

```gdscript
func setup(grid: int, patch: float, wind: Vector2, amplitude: float, seed: int) -> void
```

Builds the Phillips spectrum deterministically. n must be a power of two.

### `evaluate`

```gdscript
func evaluate(time: float) -> PackedFloat32Array
```

Returns n*n heights (row-major) at the given time.

### `displacement_image`

```gdscript
func displacement_image(time: float) -> Image
```

Heights as a single-channel float image for a displacement shader.

### `fft_1d`

```gdscript
static func fft_1d(re: PackedFloat32Array, im: PackedFloat32Array, inverse: bool) -> void
```

In-place radix-2 Cooley-Tukey FFT. Forward uses e^{-i...}; the inverse uses
e^{+i...} and scales by 1/N so inverse(forward(x)) == x.

_1 private function(s) starting with `_` are not listed._
