# sky_rainbow.gd

> Post-rain rainbow (RDR2 / Ghost of Tsushima style).

`res://scripts/client/sky_rainbow.gd`

## Overview

Post-rain rainbow (RDR2 / Ghost of Tsushima style). Physically placed in the sky
shader: primary bow at ~42 deg around the antisolar point (red outside), a
fainter reversed secondary at ~51 deg and the darker Alexander band between.
This helper only decides WHEN it shows; it costs nothing while 0.

## Functions

### `strength`

```gdscript
static func strength(storm: float, storming: bool, daylight: float, sun_height: float) -> float
```

0..1. Appears only while a storm is clearing (not building), in daylight,
with the sun below ~42 deg elevation (otherwise the bow is under the horizon).

