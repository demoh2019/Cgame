# sky_aurora.gd

> Cinematic green/violet night curtains; driven by existing world weather.

`res://scripts/client/sky_aurora.gd`

## Overview

Cinematic green/violet night curtains; driven by existing world weather.
The entire shader branch is skipped outside mountain nights or on
unsupported renderers, with stable fractional strength at transitions.

## Functions

### `strength`

```gdscript
static func strength(level: int, daylight: float, storm: float, biome: String = "mountain", method: String = "forward_plus") -> float
```

### `milky_way_strength`

```gdscript
static func milky_way_strength(level: int, daylight: float, storm: float, moon_phase: float) -> float
```

Milky Way strength: dark clear nights on High/Ultra only (dimmed while the moon is full).

