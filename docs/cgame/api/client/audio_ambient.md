# audio_ambient.gd

> Procedural weather loops and per-biome ambience beds (Unity looping Audio Sources + Mixer snapshots / Unreal Ambient Sound actors + MetaSounds noise).

`res://scripts/client/audio_ambient.gd`

## Overview

Procedural weather loops and per-biome ambience beds (Unity looping Audio Sources + Mixer snapshots /
Unreal Ambient Sound actors + MetaSounds noise). No audio files: noise is generated once.

## Constants

- `const RATE := 22050`
- `const BEDS := {`

## Functions

### `bed`

```gdscript
static func bed(biome: String, daylight: float, underground: bool) -> Dictionary
```

### `noise_stream`

```gdscript
static func noise_stream(seconds: float, smooth: float, noise_seed: int = 1) -> AudioStreamWAV
```

Looping 16-bit mono noise. `smooth` 0 = hiss (rain), toward 1 = low rumble (wind). Deterministic by seed.

### `rain_db`

```gdscript
static func rain_db(storm: float, covered: bool) -> float
```

Loop volumes (dB) from weather: rain follows storm intensity, wind its speed. Cover mutes them.

### `wind_db`

```gdscript
static func wind_db(wind_speed: float, storm: float, covered: bool) -> float
```

