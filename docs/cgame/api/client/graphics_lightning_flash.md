# graphics_lightning_flash.gd

> Event-driven storm lightning illumination.

`res://scripts/client/graphics_lightning_flash.gd`

## Overview

Event-driven storm lightning illumination. No new lights, shadow maps,
particles, sky radiance builds, draw calls, or authoritative game changes.
The existing sun/ambient/fog are briefly lifted after a real strike.

## Constants

- `const DURATION := 0.46`
- `const MAX_DISTANCE := 180.0`
- `const BASE_STRENGTH := [0.26, 0.43, 0.66, 0.88]`

## Functions

### `strength`

```gdscript
static func strength(level: int) -> float
```

Quality controls the scene-light budget, not the hazard or network event.

### `attenuation`

```gdscript
static func attenuation(distance_m: float) -> float
```

Square-root falloff makes nearby strikes dramatic and distant events subtle.

### `sample`

```gdscript
static func sample(seconds_since_strike: float, weight: float) -> float
```

Two short white/blue optical pulses (primary and softer return stroke).
This is analytic and independent of frame rate. Zero outside DURATION.

### `apply`

```gdscript
static func apply(environment: Environment, sun: DirectionalLight3D, flash: float) -> void
```

Apply after the normal day/night, fog and quality update. Never persist
augmented values: the atmosphere establishes the base again next frame.

