# cinematic_fog.gd

> Dual-path atmospheric scattering: cheap sea-level haze on every renderer and bounded screen-space froxel fog only for Forward+ on High/Ultra.

`res://scripts/client/cinematic_fog.gd`

## Overview

Dual-path atmospheric scattering: cheap sea-level haze on every renderer
and bounded screen-space froxel fog only for Forward+ on High/Ultra.
Pure profile/weather functions make GPU-independent regression possible.

## Constants

- `const MAX_HEIGHT_DENSITY := 0.0040`
- `const MAX_VOLUME_DENSITY := 0.0200`
- `const PROFILES := [`
- `const LIGHTNING_HISTORY_FLOOR := 0.12` - A lightning pulse must not be averaged into ~3/4 of the previous fog frame. Reduce history contribution only during the confirmed strike; retain a stable low-noise froxel grid for the rest of the weather simulation.

## Functions

### `profile`

```gdscript
static func profile(quality: int, method: String) -> Dictionary
```

### `weather`

```gdscript
static func weather(daylight: float, sun_height: float, storm: float, settings: Dictionary) -> Dictionary
```

No random effects or extra passes per frame. Real gameplay weather drives
the strength continuously, so abrupt transitions are never needed.

### `apply_profile`

```gdscript
static func apply_profile(env: Environment, sun: DirectionalLight3D, settings: Dictionary) -> void
```

Applied ONLY when the user changes quality or renderer. Avoids rebuilding
the volume grid on every daylight update.

### `apply_weather`

```gdscript
static func apply_weather(env: Environment, daylight: float, sun_height: float, storm: float, settings: Dictionary, horizon: Color, biome: Dictionary = {}, base_fog: Dictionary = {}) -> void
```

A single fast height-fog pass on Compatibility; the optional Forward+
fog combines with it only in a short, limited range.

### `history_for_lightning`

```gdscript
static func history_for_lightning(settings: Dictionary, flash: float) -> float
```

### `apply_lightning_history`

```gdscript
static func apply_lightning_history(env: Environment, settings: Dictionary, flash: float) -> void
```

The original Environment is reused: no second volume, post pass or light.
A tiny delta threshold prevents uploads on the long, inactive tail.

