# graphics_area_lights.gd

> Area-light softness for local lights (UE5 Source Radius, HDRP area/PCSS).

`res://scripts/client/graphics_area_lights.gd`

## Overview

Area-light softness for local lights (UE5 Source Radius, HDRP area/PCSS).
Torches, lanterns and campfires get a physical emitter size so their
shadows soften with distance; Godot's PCSS filter quality follows the tier.

## Constants

- `const GROUP := &"aa_area_light"`
- `const META_RADIUS := &"aa_area_radius"`

## Functions

### `filter_quality`

```gdscript
static func filter_quality(level: int) -> int
```

### `size_for`

```gdscript
static func size_for(level: int, emitter_radius: float) -> float
```

Emitter radius actually used: PCSS is skipped below High (it costs blocker search taps).

### `register`

```gdscript
static func register(light: Light3D, emitter_radius: float) -> void
```

### `configure`

```gdscript
static func configure(level: int, tree: SceneTree) -> void
```

_1 private function(s) starting with `_` are not listed._
