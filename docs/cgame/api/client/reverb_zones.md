# reverb_zones.gd

> Environmental reverb — the equivalent of Unity Reverb Zones / Unreal Audio Volumes.

`res://scripts/client/reverb_zones.gd`

## Overview

Environmental reverb — the equivalent of Unity Reverb Zones / Unreal Audio Volumes.
World sounds route through an "SFX" bus with one AudioEffectReverb whose room
parameters glide toward a preset chosen from where the listener stands.

## Constants

- `const BUS := "SFX"`
- `const PRESETS := {`

## Functions

### `zone_for`

```gdscript
static func zone_for(underground: bool, biome: String) -> String
```

### `ensure_bus`

```gdscript
static func ensure_bus() -> int
```

Creates the SFX bus with a reverb effect once; returns the bus index.

### `reverb`

```gdscript
static func reverb(index: int) -> AudioEffectReverb
```

### `blend`

```gdscript
static func blend(effect: AudioEffectReverb, zone: String, weight: float) -> void
```

Moves the reverb `weight` (0..1) of the way toward the zone's preset.

