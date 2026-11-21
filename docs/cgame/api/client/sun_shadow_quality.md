# sun_shadow_quality.gd

> Scalable directional-light penumbrae and weather shadow contrast.

`res://scripts/client/sun_shadow_quality.gd`

## Overview

Scalable directional-light penumbrae and weather shadow contrast.
Avoid expensive PCSS on the low-end tiers, and never select it on
Compatibility/Mobile. The sun remains the existing single light.

## Functions

### `settings`

```gdscript
static func settings(level: int, rendering_method: String) -> Dictionary
```

Godot's light_angular_distance > 0 activates directional PCSS on
Forward+. Even a visually subtle 0.6 degrees costs noticeably more.

### `opacity`

```gdscript
static func opacity(daylight: float, sun_height: float, storm: float) -> float
```

Directional shadow contrast follows actual direct illumination:
low sun, moonlight and thick cloud cover all cast weaker shadows.
This does not change shadow-map count, cascade distance or quality.

### `apply`

```gdscript
static func apply(sun: DirectionalLight3D, level: int, rendering_method: String, daylight: float, sun_height: float, storm: float) -> void
```

Configure PCSS only when the preset or renderer changes, not per frame.
Existing cascades, blur, scene shadow masks and runtime enable flags stay put.

### `update_opacity`

```gdscript
static func update_opacity(sun: DirectionalLight3D, daylight: float, sun_height: float, storm: float) -> void
```

Weather changes slowly. Calling at 5 Hz avoids redundant RenderingServer
property updates while retaining smooth fades across multiple seconds.

