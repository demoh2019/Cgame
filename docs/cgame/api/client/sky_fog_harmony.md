# sky_fog_harmony.gd

> Keep fog in the 3D world aligned with the same spectral haze as the sky.

`res://scripts/client/sky_fog_harmony.gd`

## Overview

```text
Keep fog in the 3D world aligned with the same spectral haze as the sky.
The custom Godot SkyScatteringLUT supplies only a small CPU Color sample
at the bounded sky-refresh cadence. This function adds no GPU pass/texture.

The blend matches sky.gdshader's optical-depth composition:
    shaded_sky = mix(panorama, panorama * transmission + scatter, weight)
Night and low-end renderers preserve the existing fog appearance.
```

## Functions

### `blend`

```gdscript
static func blend(base_horizon: Color, optical: Color, strength: float, daylight: float, storm: float) -> Color
```

