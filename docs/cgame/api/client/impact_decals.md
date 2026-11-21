# impact_decals.gd

> Pooled projected impact decals (blood / infected ichor / scorch) — the Godot equivalent of Unity's URP Decal Projector and Unreal's deferred decals.

`res://scripts/client/impact_decals.gd`

## Overview

Pooled projected impact decals (blood / infected ichor / scorch) — the Godot
equivalent of Unity's URP Decal Projector and Unreal's deferred decals.
A fixed ring buffer per quality tier bounds GPU cost; oldest decals are reused.

## Constants

- `const GraphicsQuality = preload("res://scripts/client/graphics_quality.gd")`
- `const BUDGET := [0, 24, 48, 96] # Low, Medium, High, Ultra.`
- `const LIFETIME := 40.0`
- `const FADE := 6.0`

## Functions

### `budget`

```gdscript
static func budget(level: int) -> int
```

### `effective_budget`

```gdscript
static func effective_budget(level: int, method: String) -> int
```

Decal projection is unsupported on the Compatibility backend. Do not
create unused GPU scene instances there, regardless of quality override.

### `draw_distance`

```gdscript
static func draw_distance(level: int) -> float
```

Large projection volumes cost screen fill rate. Limit distant splats,
scaling the fade threshold with visual quality, as in other deferred engines.

### `display_alpha`

```gdscript
static func display_alpha(age: float) -> float
```

Quantize an already-fading alpha to 8-bit precision, avoiding excessive
renderer updates at high FPS without changing full-opacity lifetimes.

### `alpha_for_age`

```gdscript
static func alpha_for_age(age: float) -> float
```

Opacity of a decal of the given age: full, then a linear fade over the last FADE seconds.

### `splat_texture`

```gdscript
static func splat_texture(seed: int) -> ImageTexture
```

### `configure`

```gdscript
func configure(level: int) -> void
```

### `splat`

```gdscript
func splat(position: Vector3, color: Color, size: float = 1.0) -> void
```

Projects a splat onto whatever lies below `position` (terrain, floors, props).

_1 private function(s) starting with `_` are not listed._
