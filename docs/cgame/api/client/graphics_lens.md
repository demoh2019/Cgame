# graphics_lens.gd

> Native camera-lens finish (engine fork: Environment.lens_*), like the "Scene Fringe" and "Film Grain" settings of Unreal Engine 5 and Unity HDRP.

`res://scripts/client/graphics_lens.gd`

## Overview

Native camera-lens finish (engine fork: Environment.lens_*), like the
"Scene Fringe" and "Film Grain" settings of Unreal Engine 5 and Unity HDRP.
Runs inside the existing Forward+ tonemap pass: no extra pass or render target.
Chromatic aberration is applied in HDR before tonemapping, grain after it;
the lens flare reuses the glow buffer, so it only appears where bloom does.

## Functions

### `settings`

```gdscript
static func settings(level: int, rendering_method: String) -> Dictionary
```

### `apply`

```gdscript
static func apply(env: Environment, level: int, rendering_method: String) -> bool
```

Returns true when the engine draws the vignette natively (the grade pass must then skip its own).

### `distortion`

```gdscript
static func distortion(level: int, rendering_method: String) -> float
```

Subtle barrel distortion of a wide real lens (UE5 Lens Distortion, HDRP
Lens Distortion). Applied in the existing canvas grade pass; kept small so
the top-down playfield stays readable.

