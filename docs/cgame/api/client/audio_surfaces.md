# audio_surfaces.gd

> Surface-dependent footsteps (Unity physic-material footsteps / Unreal Physical Surface + Footstep notifies).

`res://scripts/client/audio_surfaces.gd`

## Overview

Surface-dependent footsteps (Unity physic-material footsteps / Unreal Physical Surface + Footstep notifies).
One walking loop is shared; each surface retunes pitch, loudness and brightness of it.

## Constants

- `const PROFILES := {`

## Functions

### `surface_for`

```gdscript
static func surface_for(underground: bool, biome: String, ground_height: float, water_level: float) -> String
```

### `profile`

```gdscript
static func profile(surface: String) -> Dictionary
```

### `speed_pitch`

```gdscript
static func speed_pitch(base: float, speed: float, walk_speed: float = 4.0) -> float
```

Running steps faster: pitch of the loop follows speed relative to a walk (clamped).

