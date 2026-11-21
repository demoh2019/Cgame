# blood_decals.gd

> Ground blood splats (Diablo / Left 4 Dead): pooled native Decals project a procedurally generated splat onto terrain under hits, then fade out.

`res://scripts/client/blood_decals.gd`

## Overview

Ground blood splats (Diablo / Left 4 Dead): pooled native Decals project a
procedurally generated splat onto terrain under hits, then fade out. Decals
need Forward+/Mobile; Compatibility and Performance skip them entirely.

## Constants

- `const POOL_SIZE := 32`
- `const LIFETIME := 24.0`
- `const FADE := 4.0`

## Functions

### `enabled`

```gdscript
static func enabled(level: int, rendering_method: String) -> bool
```

Splats per hit for a tier/renderer (0 = off).

### `tint`

```gdscript
static func tint(zombie: bool) -> Color
```

Zombie ichor is dark olive (matching its spray), player blood is red.

### `splat_texture`

```gdscript
static func splat_texture() -> Texture2D
```

### `splat`

```gdscript
func splat(world, x: float, z: float, zombie: bool, damage: float) -> void
```

### `scorch`

```gdscript
func scorch(world, x: float, z: float, radius: float) -> void
```

Scorch mark (lightning strikes, explosions): a large sooty splat from the same pool.

_2 private function(s) starting with `_` are not listed._
