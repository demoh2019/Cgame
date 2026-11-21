# procedural_sounds.gd

> Procedural game sounds built on audio_graph.gd.

`res://scripts/client/procedural_sounds.gd`

## Overview

Procedural game sounds built on audio_graph.gd. Each preset returns a graph asset
(with an extra "duration" key in seconds); bake() renders and caches the AudioStreamWAV.
All graphs are original designs; DSP primitives are documented in audio_graph.gd.

## Constants

- `const AudioGraph = preload("res://scripts/client/audio_graph.gd")`
- `const SAMPLE_RATE := 22050`
- `const CACHE_LIMIT := 24`

## Functions

### `footstep`

```gdscript
static func footstep(surface: String) -> Dictionary
```

### `zombie_groan`

```gdscript
static func zombie_groan(seed: int = 0) -> Dictionary
```

Low saw voice with vibrato and random pitch wander, formant-ish lowpass sweep, breathy noise.

### `wind`

```gdscript
static func wind(intensity: float = 0.5) -> Dictionary
```

intensity in [0, 1]: louder, brighter and more gusty.

### `fire_crackle`

```gdscript
static func fire_crackle() -> Dictionary
```

Random Poisson snaps and pops on top of a dull low roar.

### `gunshot`

```gdscript
static func gunshot(caliber: String = "9mm") -> Dictionary
```

caliber: "9mm" (default), "5.56", "7.62", "12ga". Noise crack through an env-swept
lowpass, pitch-dropping thump and a short slap-back echo.

### `ui_click`

```gdscript
static func ui_click() -> Dictionary
```

### `preset_names`

```gdscript
static func preset_names() -> PackedStringArray
```

### `graph_for`

```gdscript
static func graph_for(sound: String, args: Array = [], seed: int = 0) -> Dictionary
```

### `bake`

```gdscript
static func bake(sound: String, args: Array = [], seed: int = 0) -> AudioStreamWAV
```

Renders a preset to a WAV, memoised in a small LRU cache keyed on name + args + seed.

### `cache_size`

```gdscript
static func cache_size() -> int
```

### `clear_cache`

```gdscript
static func clear_cache() -> void
```

