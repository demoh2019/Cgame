# audio_mix.gd

> Bus layout and persisted volume sliders (Unity AudioMixer groups / Unreal Sound Classes).

`res://scripts/client/audio_mix.gd`

## Overview

Bus layout and persisted volume sliders (Unity AudioMixer groups / Unreal Sound Classes).
Buses: Master, Music, SFX (reverb + low-pass, see reverb_zones.gd), UI, Ambience.

## Constants

- `const PATH := "user://albion_after_audio.cfg"`
- `const BUSES := ["Music", "UI", "Ambience"] # SFX is created by ReverbZones.`
- `const SLIDERS := ["Master", "Music", "SFX", "UI", "Ambience"]`

## Functions

### `linear_to_db`

```gdscript
static func linear_to_db(v: float) -> float
```

### `ensure_buses`

```gdscript
static func ensure_buses() -> void
```

### `ensure_lowpass`

```gdscript
static func ensure_lowpass(bus: String) -> int
```

Adds a low-pass filter as the last effect of `bus` once; returns its effect index (or -1).

### `set_volume`

```gdscript
static func set_volume(bus: String, linear: float, persist: bool = true) -> void
```

### `save`

```gdscript
static func save() -> void
```

### `load_all`

```gdscript
static func load_all() -> void
```

### `nudge`

```gdscript
static func nudge(bus: String, step: float) -> float
```

Moves the slider by `step` (0..1), snapped to 5 %; returns the new value.

