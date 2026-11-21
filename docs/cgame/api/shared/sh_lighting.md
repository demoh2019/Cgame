# sh_lighting.gd

> Static L2 spherical-harmonics lighting helpers (9 coefficients, one Color per coefficient; only r/g/b are used, alpha is kept at 0 for coefficients).

`res://scripts/shared/sh_lighting.gd`

## Overview

```text
Static L2 spherical-harmonics lighting helpers (9 coefficients, one Color per
coefficient; only r/g/b are used, alpha is kept at 0 for coefficients).

Credits (algorithms from published papers; no third-party code copied):
 - Ramamoorthi & Hanrahan, "An Efficient Representation for Irradiance
   Environment Maps" (SIGGRAPH 2001): real SH basis constants and the
   cosine-lobe convolution factors A0=pi, A1=2pi/3, A2=pi/4.
 - Peter-Pike Sloan, "Stupid Spherical Harmonics (SH) Tricks" (GDC 2008).
 - Majercik, Guertin, Nowrouzezahrai, McGuire, "Dynamic Diffuse Global
   Illumination with Ray-Traced Irradiance Fields" (JCGT 2019) for the use of
   SH irradiance probes.
The SH basis constants are mathematical facts (not copyrightable).

Convention: evaluate_irradiance() returns irradiance divided by pi, so a
uniform radiance L yields exactly L (multiply by albedo for diffuse light).
Order: Y00, Y1-1(y), Y10(z), Y11(x), Y2-2(xy), Y2-1(yz), Y20, Y21(xz), Y22.
```

## Constants

- `const COEFFS: int = 9`
- `const C0: float = 0.282094792`
- `const C1: float = 0.488602512`
- `const C2: float = 1.092548431`
- `const C3: float = 0.315391565`
- `const C4: float = 0.546274215`
- `const GOLDEN_ANGLE: float = 2.399963229728653`
- `const CONV0: float = 1.0` - Cosine convolution A_l / pi for bands 0, 1, 2.
- `const CONV1: float = 2.0 / 3.0`
- `const CONV2: float = 0.25`

## Functions

### `create`

```gdscript
static func create() -> PackedColorArray
```

### `basis`

```gdscript
static func basis(d: Vector3) -> PackedFloat32Array
```

### `fibonacci_dir`

```gdscript
static func fibonacci_dir(i: int, n: int) -> Vector3
```

Evenly distributed unit direction i of n on the sphere (Fibonacci lattice).

### `accumulate`

```gdscript
static func accumulate(sh: PackedColorArray, dir: Vector3, color: Color) -> PackedColorArray
```

Adds a radiance sample (already weighted by its solid angle) in place; returns sh.

### `project_direction`

```gdscript
static func project_direction(dir: Vector3, color: Color) -> PackedColorArray
```

Projects a single weighted radiance sample coming from `dir`.

### `add`

```gdscript
static func add(a: PackedColorArray, b: PackedColorArray) -> PackedColorArray
```

### `scale`

```gdscript
static func scale(a: PackedColorArray, f: float) -> PackedColorArray
```

### `lerp_sh`

```gdscript
static func lerp_sh(a: PackedColorArray, b: PackedColorArray, t: float) -> PackedColorArray
```

Linear blend (named lerp_sh to avoid shadowing the global lerp).

### `evaluate_radiance`

```gdscript
static func evaluate_radiance(sh: PackedColorArray, dir: Vector3) -> Color
```

Reconstructs (band-limited) radiance in direction dir.

### `evaluate_irradiance`

```gdscript
static func evaluate_irradiance(sh: PackedColorArray, normal: Vector3) -> Color
```

Cosine-convolved irradiance / pi around `normal`, clamped to be non-negative.

### `from_sky`

```gdscript
static func from_sky(sun_dir: Vector3, sun_color: Color, sky_color: Color, ground_color: Color, samples: int) -> PackedColorArray
```

Analytic sky: gradient ground->sky over the y axis plus a directional sun whose
colour is the irradiance on a surface facing it.

### `rotate`

```gdscript
static func rotate(sh: PackedColorArray, rot: Basis) -> PackedColorArray
```

Rotates the lighting function by `rot` via quadrature (error ~1e-2).

